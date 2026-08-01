import 'dart:convert';
import 'package:http/http.dart' as http;

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
      final resp = await http
          .post(
            _uri('/login'),
            // 不自动跟随重定向：登录成功后的 302 响应里带着会话 cookie，
            // 跟随会把它丢掉。
            followRedirects: false,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'username': username,
              'password': password,
            },
          )
          .timeout(const Duration(seconds: 12));
      _absorbCookies(resp);
      _loggedIn = _cookies.isNotEmpty;
      if (!_loggedIn) {
        throw WebguiSessionException(
            '登录失败：用户名/密码错误（webGUI 只允许 root 登录，且需已设置 root 密码）');
      }
      return true;
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

  /// 抓取旧版 webGUI 的磁盘 SMART 页面原始内容。
  /// 7.2.x 的页面路径以 /Main 开头；如果第一个路径不存在会自动尝试第二个。
  Future<String> fetchSmartPage(String device) async {
    await _ensureLogin();
    for (final path in ['/Main/Smart?device=$device', '/Main?device=$device']) {
      final resp = await http
          .get(_uri(path), headers: {'Cookie': _cookieHeader})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return resp.body;
      }
    }
    throw WebguiSessionException('SMART 页面抓取失败：请确认 webGUI 磁盘 SMART 页面地址');
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

/// 从 SMART 页面 HTML 中解析 smartctl -A 属性表格。
/// 兼容 <table> 和 <pre>（纯文本）两种展示形式。
List<SmartAttribute> parseSmartAttributes(String html) {
  // 去掉 HTML 标签，保留文本内容
  final text = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  final attrs = <SmartAttribute>[];
  // smartctl -A 文本格式：ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE
  final re = RegExp(
      r'^\s*(\d+)\s+([A-Za-z0-9_\-]+)\s+0x[0-9a-fA-F]+\s+(\d+)\s+(\d+)\s+(\d+)\s+([A-Za-z_\-]+)\s+\S+\s+([^\s]*)\s+(.+)$');
  for (final line in text.split('\n')) {
    final m = re.firstMatch(line);
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
