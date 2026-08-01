import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// 设置页：
/// - 服务器连接：查看地址列表、重新探测、编辑连接、断开连接
/// - WebDAV 文件管理：OpenList 地址（自动补 /dav）/ 账号 / 密码
/// - 文件缓存上限
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();

  ConnectionInfo? _connection;
  WebdavCredentials? _webdav;

  final _webdavUrlController = TextEditingController();
  final _webdavUserController = TextEditingController();
  final _webdavPassController = TextEditingController();

  double _cacheLimitMb = 500;
  bool _loading = true;
  bool _webdavBusy = false;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _webdavUrlController.dispose();
    _webdavUserController.dispose();
    _webdavPassController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final conn = await _storage.loadConnection();
    final webdav = await _storage.loadWebdav();
    final cacheMb = await _storage.loadCacheLimitMb();
    if (!mounted) return;
    setState(() {
      _connection = conn;
      _webdav = webdav;
      if (webdav != null) {
        _webdavUrlController.text = webdav.url;
        _webdavUserController.text = webdav.username;
        _webdavPassController.text = webdav.password;
      }
      _cacheLimitMb = cacheMb.toDouble();
      _loading = false;
    });
  }

  // -------------------- 服务器连接 --------------------

  Future<void> _reprobe() async {
    final conn = _connection;
    if (conn == null) return;
    setState(() => _probing = true);
    final best = await UnraidApi.probeBestAddress(conn.addresses, conn.apiKey);
    if (!mounted) return;
    setState(() => _probing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        best != null ? '连接正常，当前使用：$best' : '所有地址均无法连接，请检查网络或地址配置',
      ),
    ));
  }

  Future<void> _editConnection() async {
    // 登录页连接成功后会重建整个页面栈（新的 HomeScreen），设置页随之关闭
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('断开连接？'),
        content: const Text('会清除保存的服务器地址、API Key 和 WebDAV 配置，需要重新填写。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // -------------------- WebDAV --------------------

  Future<void> _testWebdav() async {
    final creds = _readWebdavForm();
    if (creds == null) return;
    setState(() => _webdavBusy = true);
    try {
      await WebdavService(creds).testConnection();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接成功')));
      }
    } on WebdavException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  Future<void> _saveWebdav() async {
    final creds = _readWebdavForm();
    if (creds == null) return;
    setState(() => _webdavBusy = true);
    try {
      await WebdavService(creds).testConnection();
      await _storage.saveWebdav(creds);
      if (mounted) {
        setState(() => _webdav = creds);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } on WebdavException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  Future<void> _clearWebdav() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('清除 WebDAV 配置？'),
        content: const Text('会删除保存的地址和密码。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.clearWebdav();
    if (!mounted) return;
    setState(() {
      _webdav = null;
      _webdavUrlController.clear();
      _webdavUserController.clear();
      _webdavPassController.clear();
    });
  }

  WebdavCredentials? _readWebdavForm() {
    final url = _webdavUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写 WebDAV 地址')));
      return null;
    }
    return WebdavCredentials(
      url: WebdavCredentials.normalizeUrl(url),
      username: _webdavUserController.text.trim(),
      password: _webdavPassController.text,
    );
  }

  // -------------------- 缓存上限 --------------------

  Future<void> _onCacheChanged(double value) async {
    setState(() => _cacheLimitMb = value);
    await _storage.saveCacheLimitMb(value.round());
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildConnectionCard(),
                const SizedBox(height: 16),
                _buildWebdavCard(),
                const SizedBox(height: 16),
                _buildCacheCard(),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '提示：服务器地址和 WebDAV 地址相互独立，可以指向不同的主机/端口。',
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConnectionCard() {
    final conn = _connection;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text('服务器连接',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (conn == null || conn.addresses.isEmpty)
            const Text('未配置连接',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13))
          else
            ...conn.addresses.map((addr) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 7, color: AppColors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(addr,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _probing ? null : _reprobe,
                  icon: _probing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('重新探测'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editConnection,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('编辑'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _disconnect,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('断开'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebdavCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text('WebDAV 文件管理',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          const Text('OpenList 或其他 WebDAV 服务。地址只填主页地址即可，/dav 会自动补全。',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _webdavUrlController,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: '例如 192.168.1.10:5244',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webdavUserController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webdavPassController,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _webdavBusy ? null : _testWebdav,
                  icon: const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('测试'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _webdavBusy ? null : _saveWebdav,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearWebdav,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('清除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCacheCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_storage_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                '文件缓存上限',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _cacheLimitMb >= 1000
                    ? '${(_cacheLimitMb / 1000).toStringAsFixed(1)} GB'
                    : '${_cacheLimitMb.round()} MB',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '文件管理里下载/预览过的文件会缓存在本地，超过这个上限后会自动清理最早的缓存。拖动滑块实时生效。',
            style: TextStyle(
                fontSize: 12.5, color: AppColors.textFaint, height: 1.5),
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.orange,
              thumbColor: AppColors.orange,
              inactiveTrackColor: AppColors.border,
              overlayColor: AppColors.orange.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: _cacheLimitMb,
              min: 50,
              max: 5000,
              divisions: 99,
              onChanged: _onCacheChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('50 MB',
                  style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
              Text('5 GB',
                  style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
