import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/network_metrics.dart';

/// 通过 Unraid webGUI 的账号密码会话访问旧版 PHP 端点。
///
/// 官方 GraphQL API 没有提供的能力（整机重启/关机、SMART 明细、
/// 系统更新检测等）都通过这套会话走旧版 webGUI 端点实现。
/// 流程与浏览器一致：POST /login 拿会话 cookie → 带 cookie 调旧端点。
///
/// 注意：webGUI 登录只允许 root 用户，且需要已在 Unraid 里设置 root 密码。
class WebguiSessionException implements Exception {
  final String message;
  WebguiSessionException(this.message);
  @override
  String toString() => message;
}

/// 一条 SMART 属性（smartctl -A 表格的一行）
class SmartAttribute {
  final int id;
  final String name;
  final int value;
  final int worst;
  final int threshold;
  final String type; // Pre-fail / Old_age
  final String whenFailed;
  final String rawValue;

  SmartAttribute({
    required this.id,
    required this.name,
    required this.value,
    required this.worst,
    required this.threshold,
    required this.type,
    required this.whenFailed,
    required this.rawValue,
  });
}

class WebguiSession {
  final String baseUrl;
  final String username;
  final String password;

  final Map<String, String> _cookies = {};
  bool _loggedIn = false;

  WebguiSession({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  bool get isLoggedIn => _loggedIn && _cookies.isNotEmpty;

  String get _origin =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Uri _uri(String path) => Uri.parse('$_origin$path');

  /// 吸收响应里的 Set-Cookie（兼容多个 cookie 头被合并的情况）
  void _absorbCookies(http.Response resp) {
    resp.headers.forEach((key, value) {
      if (key.toLowerCase() == 'set-cookie') {
        for (final chunk in value.split(',')) {
          final parts = chunk.split(';');
          final kv = parts.first.trim();
          final eq = kv.indexOf('=');
          if (eq > 0) {
            _cookies[kv.substring(0, eq).trim()] = kv.substring(eq + 1).trim();
          }
        }
      }
    });
  }

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// 账号密码登录 webGUI，拿会话 cookie。
  Future<bool> login() async {
    _cookies.clear();
    _loggedIn = false;
    try {
      final client = http.Client();
      try {
        final req = http.Request('POST', _uri('/login'));
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded';
        req.body =
            'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';
        // 不自动跟随重定向：登录成功后的 302 响应里带着会话 cookie，
        // 自动跟随会把中间响应的 Set-Cookie 丢掉。
        req.followRedirects = false;
        final streamed =
            await client.send(req).timeout(const Duration(seconds: 12));
        final resp = await http.Response.fromStream(streamed);
        _absorbCookies(resp);
        _loggedIn = _cookies.isNotEmpty;
        if (!_loggedIn) {
          throw WebguiSessionException(
              '登录失败：用户名/密码错误（webGUI 只允许 root 登录，且需已设置 root 密码）');
        }
        return true;
      } finally {
        client.close();
      }
    } on WebguiSessionException {
      rethrow;
    } catch (e) {
      throw WebguiSessionException('无法连接服务器：$e');
    }
  }

  Future<void> _ensureLogin() async {
    if (!isLoggedIn) {
      await login();
    }
  }

  /// 整机重启 / 关机。cmd: reboot（重启）| powerdown（关机）
  Future<void> sendBootCommand(String cmd) async {
    await _ensureLogin();
    final resp = await http
        .post(
          _uri('/webGui/include/Boot.php'),
          headers: {'Cookie': _cookieHeader},
          body: {'cmd': cmd},
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode >= 400) {
      throw WebguiSessionException('电源命令失败：HTTP ${resp.statusCode}');
    }
  }

  /// 抓取磁盘 SMART 完整属性。
  /// 7.2.x 的 dynamix 磁盘页路径为 /Dashboard/Main?name=<磁盘名>（如 disk1），
  /// SMART 属性在 tab3（cookie: one=tab3），内容服务端渲染。
  Future<List<SmartAttribute>> fetchSmartAttributes(String diskName) async {
    await _ensureLogin();
    final tried = <String>{};
    final candidates = <String>[
      '/Dashboard/Main?name=$diskName',
      '/Main?name=$diskName',
      '/Dashboard/Main/Settings/Device?name=$diskName',
    ];
    while (candidates.isNotEmpty && tried.length < 5) {
      final path = candidates.removeAt(0);
      if (!tried.contains(path)) {
        tried.add(path);
      } else {
        continue;
      }
      String body;
      try {
        final resp = await http
            .get(
              _uri(path),
              headers: {
                // one=tab3：SMART 属性页签（dynamix 按 cookie 渲染对应 tab）
                'Cookie': 'one=tab3; $_cookieHeader',
              },
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        body = resp.body;
      } catch (_) {
        continue;
      }
      final attrs = parseSmartAttributes(body);
      if (attrs.isNotEmpty) return attrs;
      // 从页面里挖 smart 相关端点，继续尝试
      for (final f in _discoverEndpoints(body)) {
        if (!tried.contains(f)) candidates.add(f);
      }
    }
    throw WebguiSessionException(
        'SMART 页面格式无法解析：自动发现的端点都拿不到属性数据');
  }

  /// 从页面 HTML/JS 里挖出 smart 相关的路径端点
  List<String> _discoverEndpoints(String html) {
    final found = <String>{};
    final re = RegExp(
        r'''["']([^"']*[Ss]mart[^"']*)["']''');
    for (final m in re.allMatches(html)) {
      final raw = m.group(1)!;
      final u = raw.contains('://') ? Uri.tryParse(raw)?.path ?? '' : raw;
      if (u.isEmpty || u.startsWith('/webGui/images') || u.startsWith('/webGui/css')) {
        continue;
      }
      found.add(u.startsWith('/') ? u : '/$u');
    }
    return found.toList();
  }

  /// 通过 nchan 频道抓取实时网络速率（仪表盘数据源）。
  /// dynamix 仪表盘的网络面板订阅 /sub/update3，消息为 JSON，port 数组形如
  /// [['eth0', '198.1 Kbps', '142.7 Kbps', ...], ...]
  /// （第 2/3 项是格式化字符串速率，单位是 Kbps/Mbps/Gbps——注意是比特/秒）。
  /// nchan 支持 GET 长轮询，带会话 cookie 即可读取。
  Future<List<NetworkRateInfo>> fetchNchanNetworkRates() async {
    await _ensureLogin();
    final resp = await http
        .get(
          _uri('/sub/update3?timeout=1'),
          headers: {'Cookie': _cookieHeader},
        )
        .timeout(const Duration(seconds: 3));
    if (resp.statusCode != 200 || resp.body.trim().isEmpty) {
      throw WebguiSessionException('nchan 无数据');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final ports = (json['port'] as List?) ?? [];
    final rates = <NetworkRateInfo>[];
    for (final p in ports) {
      final arr = p as List;
      if (arr.isEmpty) continue;
      final name = arr[0].toString();
      // 过滤回环/虚拟网口，只保留物理网口
      if (name == 'lo' ||
          name.startsWith('veth') ||
          name.startsWith('docker') ||
          name.startsWith('br-')) {
        continue;
      }
      rates.add(NetworkRateInfo(
        name: name,
        operstate: null,
        rxSec: _parseRateString(arr.length > 1 ? arr[1].toString() : ''),
        txSec: _parseRateString(arr.length > 2 ? arr[2].toString() : ''),
        utilizationPercent: null,
        lastUpdated: DateTime.now(),
      ));
    }
    if (rates.isEmpty) {
      throw WebguiSessionException('nchan 无端口数据');
    }
    return rates;
  }

  /// 解析 "198.1 Kbps" / "1.2 Mbps" / "12.3 MB/s" 这类格式化速率字符串 → 字节/秒。
  /// bps 结尾的是比特/秒，需要 ÷8 转成字节/秒。
  static double _parseRateString(String s) {
    final m = RegExp(
            r'^([\d.]+)\s*([kMGTPE]?)(?:i)?(?:bps|Bps|b/s|B/s)$',
            caseSensitive: false)
        .firstMatch(s.trim());
    if (m == null) return 0;
    final v = double.tryParse(m.group(1)!) ?? 0;
    const mult = {
      '': 1.0,
      'k': 1e3,
      'M': 1e6,
      'G': 1e9,
      'T': 1e12,
      'P': 1e15,
      'E': 1e18,
    };
    final raw = v * (mult[m.group(2)!.toLowerCase()] ?? 1);
    final isBits = s.trim().toLowerCase().endsWith('bps');
    return isBits ? raw / 8 : raw;
  }

  /// 系统更新检测（旧版端点，json=true 返回可用更新信息）
  Future<Map<String, dynamic>?> fetchOsUpdateInfo() async {
    await _ensureLogin();
    final resp = await http
        .get(
          _uri('/plugins/dynamix.plugin.manager/include/UnraidCheckExec.php?json=true'),
          headers: {'Cookie': _cookieHeader},
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// 从 SMART 页面 HTML 中解析 smartctl -A 属性表。
/// 依次尝试三种格式：
/// 1) HTML <table>（按表头对齐列）
/// 2) smartctl -A 纯文本（单行一条属性）
/// 3) 宽松匹配（无 ID/无 0x 标志位的变体）
List<SmartAttribute> parseSmartAttributes(String html) {
  final table = _parseFromTable(html);
  if (table.isNotEmpty) return table;

  final text = _stripTags(html);
  final attrs = _parseFromText(text);
  if (attrs.isNotEmpty) return attrs;

  return _parseFromTextLoose(text);
}

List<SmartAttribute> _parseFromTable(String html) {
  final rows = <List<String>>[];
  final trRe = RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false);
  for (final tr in trRe.allMatches(html)) {
    final cells = <String>[];
    final tdRe = RegExp(r'<t[dh][^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false);
    for (final td in tdRe.allMatches(tr.group(1)!)) {
      cells.add(_stripTags(td.group(1)!).trim());
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return [];

  // 找表头行，确定各列位置
  int? nameIdx, valueIdx, worstIdx, threshIdx, rawIdx;
  for (final row in rows) {
    final low = row.map((c) => c.toLowerCase()).toList();
    final hasAttr = low.any((c) => c.contains('attribute'));
    if (!hasAttr) continue;
    nameIdx = low.indexWhere((c) => c.contains('attribute'));
    valueIdx = low.indexWhere((c) => c == 'value' || c == 'val');
    worstIdx = low.indexWhere((c) => c.contains('worst'));
    threshIdx = low.indexWhere((c) => c.contains('thresh'));
    rawIdx = low.indexWhere((c) => c.contains('raw'));
    break;
  }
  if (nameIdx == null) return [];

  String cell(List<String> row, int? idx, String fallback) =>
      (idx != null && idx < row.length) ? row[idx] : fallback;

  final attrs = <SmartAttribute>[];
  for (final row in rows) {
    final id = int.tryParse(row.first.trim());
    if (id == null || row.length <= nameIdx) continue;
    attrs.add(SmartAttribute(
      id: id,
      name: cell(row, nameIdx, ''),
      value: int.tryParse(cell(row, valueIdx, '0')) ?? 0,
      worst: int.tryParse(cell(row, worstIdx, '0')) ?? 0,
      threshold: int.tryParse(cell(row, threshIdx, '0')) ?? 0,
      type: '',
      whenFailed: '',
      rawValue: cell(row, rawIdx, ''),
    ));
  }
  return attrs;
}

List<SmartAttribute> _parseFromText(String text) {
  final attrs = <SmartAttribute>[];
  // ID ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE
  final re = RegExp(
      r'^\s*(\d+)\s+([A-Za-z0-9_\-]+)\s+0x[0-9a-fA-F]+\s+(\d+)\s+(\d+)\s+(\d+)\s+([A-Za-z_\-]+)\s+\S+\s+(\S*)\s*(.*)$');
  for (final line in text.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    attrs.add(SmartAttribute(
      id: int.parse(m.group(1)!),
      name: m.group(2)!,
      value: int.parse(m.group(3)!),
      worst: int.parse(m.group(4)!),
      threshold: int.parse(m.group(5)!),
      type: m.group(6)!,
      whenFailed: m.group(7)!,
      rawValue: m.group(8)!.trim(),
    ));
  }
  return attrs;
}

/// 宽松模式：允许没有 ID 号、没有 0x 标志位的行
List<SmartAttribute> _parseFromTextLoose(String text) {
  final attrs = <SmartAttribute>[];
  final re = RegExp(
      r'^\s*([A-Za-z0-9_\-]+)\s+(?:0x[0-9a-fA-F]+\s+)?(\d+)\s+(\d+)\s+(\d+)(?:\s+([A-Za-z_\-]+))?(?:\s+\S+)?(?:\s+(\S*))?\s*(.*)$');
  for (final line in text.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    final name = m.group(1)!;
    if (name.toLowerCase() == 'attribute' ||
        name.toLowerCase().contains('raw_read') == false && int.tryParse(name) != null) {
      continue;
    }
    final id = int.tryParse(name);
    if (id != null) continue; // 首列是数字时交给标准解析
    attrs.add(SmartAttribute(
      id: 0,
      name: name,
      value: int.parse(m.group(2)!),
      worst: int.parse(m.group(3)!),
      threshold: int.parse(m.group(4)!),
      type: m.group(5) ?? '',
      whenFailed: m.group(6) ?? '',
      rawValue: m.group(7)?.trim() ?? '',
    ));
  }
  return attrs;
}

String _stripTags(String html) {
  return html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
