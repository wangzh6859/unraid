import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/system_stats.dart';
import '../models/network_metrics.dart';
import '../models/docker_container.dart';
import '../models/vm_domain.dart';

/// 与 Unraid 官方 GraphQL API 通信的客户端。
///
/// 接口文档：Settings → Management Access → Developer Options 中开启
/// GraphQL Sandbox 后，端点固定为 <baseUrl>/graphql，
/// 鉴权通过请求头 `x-api-key` 传递。
///
/// 查询按数据域拆成多个独立的小查询（系统信息 / 阵列 / 指标 / 网速），
/// 互不影响：某个字段在当前 Unraid 版本不存在时，只影响对应区域，
/// 不会像"一个大查询"那样整个失败。
class UnraidApiException implements Exception {
  final String message;
  UnraidApiException(this.message);
  @override
  String toString() => message;
}

class UnraidApi {
  final String baseUrl; // 完整基础地址，如 http://192.168.1.10 或 https://nas.example.com
  final String apiKey;

  UnraidApi({required this.baseUrl, required this.apiKey});

  /// 规范化地址：没写协议时自动补 http://（登录页保存前调用）。
  static String normalizeAddress(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'http://$s';
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  Uri get _endpoint {
    final trimmed =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$trimmed/graphql');
  }

  Future<Map<String, dynamic>> _post(
    String query, {
    Map<String, dynamic>? variables,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    http.Response resp;
    try {
      resp = await http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
            },
            body: jsonEncode({
              'query': query,
              if (variables != null) 'variables': variables,
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw UnraidApiException('无法连接到 NAS，请检查地址和网络：$e');
    }

    if (resp.statusCode == 401) {
      throw UnraidApiException('API Key 无效，请检查是否填写正确');
    }

    // 无论状态码是什么，都先尝试解析 body——Apollo Server 在字段权限不足、
    // 查询验证失败等情况下也会把具体错误信息放在 JSON body 的 errors 里，
    // 直接按 HTTP 状态码报错会丢失这些关键诊断信息。
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    if (body != null && body['errors'] != null) {
      final errors = body['errors'] as List;
      final firstError = errors.isNotEmpty ? errors.first : null;
      final msg = firstError is Map ? (firstError['message'] ?? '未知错误') : '未知错误';
      // 常见的权限类报错，给出更好懂的中文提示
      final msgStr = msg.toString();
      if (msgStr.toLowerCase().contains('forbidden') ||
          msgStr.toLowerCase().contains('permission') ||
          msgStr.toLowerCase().contains('unauthorized')) {
        throw UnraidApiException(
            '权限不足：请检查 Unraid 里这个 API Key 的角色/权限是否包含对应资源的读取权限（$msgStr）');
      }
      throw UnraidApiException('接口返回错误：$msgStr');
    }

    if (resp.statusCode == 403) {
      throw UnraidApiException('权限不足：这个 API Key 没有访问该资源的权限');
    }
    if (resp.statusCode != 200) {
      throw UnraidApiException(
          '服务器返回错误：HTTP ${resp.statusCode}${body == null ? '（响应内容：${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}）' : ''}');
    }

    return (body?['data'] as Map<String, dynamic>?) ?? {};
  }

  /// 校验连接是否有效（用于登录页测试连接 / 多地址探测）。
  /// [timeout] 可传短超时，加快多地址探测的整体速度。
  Future<String> testConnection({Duration timeout = const Duration(seconds: 12)}) async {
    const query = r'''
      query TestConnection {
        info { os { hostname } }
      }
    ''';
    final data = await _post(query, timeout: timeout);
    return data['info']?['os']?['hostname'] ?? 'Unraid';
  }

  /// 多地址自动探测：并行尝试所有地址，按用户填写的顺序返回第一个可达的。
  /// 全部不可达返回 null。
  static Future<String?> probeBestAddress(
    List<String> addresses,
    String apiKey, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (addresses.isEmpty) return null;
    final results = await Future.wait(
      addresses.map((addr) async {
        try {
          final api = UnraidApi(baseUrl: addr, apiKey: apiKey);
          await api.testConnection(timeout: timeout);
          return (addr, true);
        } catch (_) {
          return (addr, false);
        }
      }),
    );
    for (final (addr, ok) in results) {
      if (ok) return addr;
    }
    return null;
  }

  // -------------------- 系统信息（主机名 / CPU / 网卡静态信息）--------------------

  Future<SystemInfoSnapshot> fetchSystemInfo() async {
    const query = r'''
      query SystemInfo {
        info {
          os { hostname distro uptime }
          cpu { manufacturer brand cores threads speed packages { temp totalPower } }
          devices {
            network { iface model speed }
            gpu { type vendorname productid class }
          }
        }
      }
    ''';
    final data = await _post(query);
    return SystemInfoSnapshot.fromJson(data);
  }

  // -------------------- 阵列 + 磁盘（容量 / 温度 / 状态 / SMART）--------------------

  Future<ArraySnapshot> fetchArraySnapshot() async {
    const query = r'''
      query ArrayAndDisks {
        array {
          state
          capacity { kilobytes { free used total } }
          disks { name device status temp type fsSize fsUsed isSpinning }
          caches { name device status temp type fsSize fsUsed isSpinning }
        }
        disks {
          device
          vendor
          smartStatus
          interfaceType
          serialNum
        }
      }
    ''';
    final data = await _post(query);
    return ArraySnapshot.fromJson(data);
  }

  // -------------------- 实时指标（CPU / 内存占用）--------------------

  /// 温度传感器（CPU/GPU/磁盘/主板，来自 lm-sensors / smartctl / ipmi）
  Future<List<TemperatureSensor>> fetchTemperatureSensors() async {
    const query = r'''
      query TemperatureSensors {
        metrics {
          temperature {
            sensors {
              name
              type
              current { value unit status }
            }
          }
        }
      }
    ''';
    final data = await _post(query);
    final list = (data['metrics']?['temperature']?['sensors'] as List?) ?? [];
    return list
        .map((e) => TemperatureSensor.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MetricsSnapshot> fetchMetricsSnapshot() async {
    const query = r'''
      query LiveMetrics {
        metrics {
          cpu { percentTotal }
          memory { percentTotal total used available }
        }
      }
    ''';
    final data = await _post(query);
    return MetricsSnapshot.fromJson(data);
  }

  // -------------------- 实时网络速率（较新版本 Unraid 才有，失败时上层降级）--------------------

  Future<List<NetworkRateInfo>> fetchNetworkRates() async {
    const query = r'''
      query NetworkRates {
        metrics {
          network { name operstate rxSec txSec utilizationPercent lastUpdated }
        }
      }
    ''';
    final data = await _post(query);
    final list = (data['metrics']?['network'] as List?) ?? [];
    return list
        .map((e) => NetworkRateInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -------------------- Docker 容器 --------------------

  Future<List<DockerContainerInfo>> fetchContainers() async {
    const query = r'''
      query Containers {
        docker {
          containers {
            id
            names
            image
            state
            status
            autoStart
          }
        }
      }
    ''';
    final data = await _post(query);
    final list = (data['docker']?['containers'] as List?) ?? [];
    return list
        .map((c) => DockerContainerInfo.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> startContainer(String id) async {
    const query = r'''
      mutation StartContainer($id: PrefixedID!) {
        docker { start(id: $id) { id state } }
      }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> stopContainer(String id) async {
    const query = r'''
      mutation StopContainer($id: PrefixedID!) {
        docker { stop(id: $id) { id state } }
      }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> pauseContainer(String id) async {
    const query = r'''
      mutation PauseContainer($id: PrefixedID!) {
        docker { pause(id: $id) { id state } }
      }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> unpauseContainer(String id) async {
    const query = r'''
      mutation UnpauseContainer($id: PrefixedID!) {
        docker { unpause(id: $id) { id state } }
      }
    ''';
    await _post(query, variables: {'id': id});
  }

  // -------------------- 虚拟机 --------------------

  Future<List<VmDomainInfo>> fetchVms() async {
    const query = r'''
      query VMs {
        vms { domains { id name state } }
      }
    ''';
    final data = await _post(query);
    final list = (data['vms']?['domains'] as List?) ?? [];
    return list
        .map((v) => VmDomainInfo.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> startVm(String id) async {
    const query = r'''
      mutation StartVm($id: PrefixedID!) { vm { start(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> stopVm(String id) async {
    const query = r'''
      mutation StopVm($id: PrefixedID!) { vm { stop(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> pauseVm(String id) async {
    const query = r'''
      mutation PauseVm($id: PrefixedID!) { vm { pause(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> resumeVm(String id) async {
    const query = r'''
      mutation ResumeVm($id: PrefixedID!) { vm { resume(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> forceStopVm(String id) async {
    const query = r'''
      mutation ForceStopVm($id: PrefixedID!) { vm { forceStop(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  Future<void> rebootVm(String id) async {
    const query = r'''
      mutation RebootVm($id: PrefixedID!) { vm { reboot(id: $id) } }
    ''';
    await _post(query, variables: {'id': id});
  }

  // -------------------- 阵列（Array）--------------------
  // 注意：官方 API 目前只提供"阵列启动/停止"，不提供整机重启/关机的接口。

  Future<void> setArrayState(bool start) async {
    const query = r'''
      mutation SetArrayState($desiredState: ArrayStateInputState!) {
        array { setState(input: { desiredState: $desiredState }) { state } }
      }
    ''';
    await _post(query, variables: {
      'desiredState': start ? 'START' : 'STOP',
    });
  }
}
