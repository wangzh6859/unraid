import 'package:shared_preferences/shared_preferences.dart';
import 'webdav_service.dart';

/// 服务器连接信息：一个 API Key 对应多个可选地址（局域网 / 外网 HTTPS），
/// App 启动时自动探测哪个地址当前可达。
class ConnectionInfo {
  final String apiKey;
  final List<String> addresses; // 完整地址，如 http://192.168.1.10 / https://nas.example.com

  ConnectionInfo({required this.apiKey, required this.addresses});
}

/// 负责在设备本地保存/读取连接信息。
///
/// 注意：这里使用 SharedPreferences（明文存储在应用私有目录），
/// 对于个人局域网/家庭场景足够方便。如果你希望更强的安全性，
/// 可以后续替换为 flutter_secure_storage。
class StorageService {
  static const _keyApiKey = 'unraid_api_key';
  static const _keyAddresses = 'unraid_addresses';

  // 旧版字段（仅用于一次性迁移到多地址模型）
  static const _legacyKeyHost = 'unraid_host';
  static const _legacyKeyUseHttps = 'unraid_use_https';

  static const _keyWebdavUrl = 'webdav_url';
  static const _keyWebdavUsername = 'webdav_username';
  static const _keyWebdavPassword = 'webdav_password';

  static const _keyCacheLimitMb = 'cache_limit_mb';
  static const _defaultCacheLimitMb = 500;

  Future<void> saveConnection({
    required String apiKey,
    required List<String> addresses,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setStringList(_keyAddresses, addresses);
  }

  Future<ConnectionInfo?> loadConnection() async {
    final prefs = await SharedPreferences.getInstance();

    var addresses = prefs.getStringList(_keyAddresses);

    // 兼容旧版本的单地址存储：读出来后转成多地址格式并迁移。
    if (addresses == null || addresses.isEmpty) {
      final legacyHost = prefs.getString(_legacyKeyHost);
      if (legacyHost != null && legacyHost.isNotEmpty) {
        final useHttps = prefs.getBool(_legacyKeyUseHttps) ?? false;
        addresses = ['${useHttps ? 'https' : 'http'}://$legacyHost'];
        await prefs.setStringList(_keyAddresses, addresses);
        await prefs.remove(_legacyKeyHost);
        await prefs.remove(_legacyKeyUseHttps);
      }
    }

    final apiKey = prefs.getString(_keyApiKey);
    if (apiKey == null || apiKey.isEmpty || addresses == null || addresses.isEmpty) {
      return null;
    }
    return ConnectionInfo(apiKey: apiKey, addresses: addresses);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyApiKey);
    await prefs.remove(_keyAddresses);
    await prefs.remove(_legacyKeyHost);
    await prefs.remove(_legacyKeyUseHttps);
    await clearWebdav();
  }

  // -------------------- WebDAV（文件管理，比如 OpenList）--------------------

  Future<void> saveWebdav(WebdavCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWebdavUrl, creds.url);
    await prefs.setString(_keyWebdavUsername, creds.username);
    await prefs.setString(_keyWebdavPassword, creds.password);
  }

  Future<WebdavCredentials?> loadWebdav() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyWebdavUrl);
    final username = prefs.getString(_keyWebdavUsername);
    final password = prefs.getString(_keyWebdavPassword);
    if (url == null || url.isEmpty) return null;
    return WebdavCredentials(
      url: url,
      username: username ?? '',
      password: password ?? '',
    );
  }

  Future<void> clearWebdav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWebdavUrl);
    await prefs.remove(_keyWebdavUsername);
    await prefs.remove(_keyWebdavPassword);
  }

  // -------------------- App 设置：文件预览/缓存上限（MB，可实时调整）--------------------

  Future<int> loadCacheLimitMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCacheLimitMb) ?? _defaultCacheLimitMb;
  }

  Future<void> saveCacheLimitMb(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCacheLimitMb, mb);
  }
}
