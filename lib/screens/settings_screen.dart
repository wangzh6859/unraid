import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../services/webdav_service.dart';
import '../services/webgui_session.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// 设置页（所有登录/连接配置都集中在这里，改动保存后实时生效）：
/// - 服务器连接：地址列表编辑 + API Key + 保存并应用 / 重新探测 / 断开连接
/// - WebDAV 文件管理：OpenList 地址（自动补 /dav）/ 账号 / 密码
/// - 主题：深色/浅色/跟随系统 × 强调色
/// - 下载保存位置：缓存目录（自动清理）/ 文档目录（持久保存）
/// - 文件缓存上限
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();

  final List<TextEditingController> _addressControllers = [
    TextEditingController(),
  ];
  final _apiKeyController = TextEditingController();

  final _webdavUrlController = TextEditingController();
  final _webdavUserController = TextEditingController();
  final _webdavPassController = TextEditingController();

  final _webguiUserController = TextEditingController(text: 'root');
  final _webguiPassController = TextEditingController();

  double _cacheLimitMb = 500;
  int _themePresetIndex = 0;
  int _saveLocation = StorageService.saveLocationCache;
  String? _saveLocationPath;

  bool _loading = true;
  bool _probing = false;
  bool _savingConnection = false;
  bool _webdavBusy = false;
  bool _webguiBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _addressControllers) {
      c.dispose();
    }
    _apiKeyController.dispose();
    _webdavUrlController.dispose();
    _webdavUserController.dispose();
    _webdavPassController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final conn = await _storage.loadConnection();
    final webdav = await _storage.loadWebdav();
    final cacheMb = await _storage.loadCacheLimitMb();
    final themeIdx = await _storage.loadThemePresetIndex();
    final saveLoc = await _storage.loadSaveLocation();
    final saveLocPath = await _storage.loadSaveLocationPath();
    final wg = await _storage.loadWebgui();
    if (!mounted) return;

    setState(() {
      if (conn != null) {
        _apiKeyController.text = conn.apiKey;
        for (var i = 0; i < conn.addresses.length; i++) {
          if (i < _addressControllers.length) {
            _addressControllers[i].text = conn.addresses[i];
          } else {
            _addressControllers.add(TextEditingController(text: conn.addresses[i]));
          }
        }
      }
      if (webdav != null) {
        _webdavUrlController.text = webdav.url;
        _webdavUserController.text = webdav.username;
        _webdavPassController.text = webdav.password;
      }
      if (wg != null) {
        _webguiUserController.text = wg.username;
        _webguiPassController.text = wg.password;
      }
      _cacheLimitMb = cacheMb.toDouble();
      _themePresetIndex = themeIdx;
      _saveLocation = saveLoc;
      _saveLocationPath = saveLocPath;
      _loading = false;
    });
  }

  // -------------------- 服务器连接 --------------------

  void _addAddressField() {
    setState(() => _addressControllers.add(TextEditingController()));
  }

  void _removeAddressField(int index) {
    if (_addressControllers.length <= 1) return;
    setState(() {
      _addressControllers[index].dispose();
      _addressControllers.removeAt(index);
    });
  }

  List<String> get _enteredAddresses => _addressControllers
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .map(UnraidApi.normalizeAddress)
      .toList();

  Future<void> _saveAndApplyConnection() async {
    final apiKey = _apiKeyController.text.trim();
    final addresses = _enteredAddresses;
    if (addresses.isEmpty || apiKey.isEmpty) {
      _toast('请至少填写一个服务器地址和 API Key');
      return;
    }

    setState(() => _savingConnection = true);
    // 保存并当场探测，确认当前可用地址
    final best = await UnraidApi.probeBestAddress(addresses, apiKey);
    if (!mounted) return;
    setState(() => _savingConnection = false);

    if (best == null) {
      _toast('所有地址都无法连接，仍已保存配置；回到主页会显示具体错误');
    } else {
      _toast('连接正常，当前使用：$best');
    }
    await _storage.saveConnection(apiKey: apiKey, addresses: addresses);
  }

  Future<void> _reprobe() async {
    final apiKey = _apiKeyController.text.trim();
    final addresses = _enteredAddresses;
    if (addresses.isEmpty || apiKey.isEmpty) {
      _toast('请先填写地址和 API Key');
      return;
    }
    setState(() => _probing = true);
    final best = await UnraidApi.probeBestAddress(addresses, apiKey);
    if (!mounted) return;
    setState(() => _probing = false);
    _toast(best != null ? '连接正常，当前使用：$best' : '所有地址均无法连接，请检查网络或地址配置');
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
      if (mounted) _toast('连接成功');
    } on WebdavException catch (e) {
      if (mounted) _toast(e.message);
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
      if (mounted) _toast('已保存');
    } on WebdavException catch (e) {
      if (mounted) _toast(e.message);
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
      _webdavUrlController.clear();
      _webdavUserController.clear();
      _webdavPassController.clear();
    });
  }

  WebdavCredentials? _readWebdavForm() {
    final url = _webdavUrlController.text.trim();
    if (url.isEmpty) {
      _toast('请填写 WebDAV 地址');
      return null;
    }
    return WebdavCredentials(
      url: WebdavCredentials.normalizeUrl(url),
      username: _webdavUserController.text.trim(),
      password: _webdavPassController.text,
    );
  }

  // -------------------- webGUI 系统登录 --------------------

  String? get _activeAddress =>
      _enteredAddresses.isNotEmpty ? _enteredAddresses.first : null;

  Future<WebguiSession?> _buildWebguiSession() async {
    final address = _activeAddress;
    if (address == null) {
      _toast('请先填写服务器地址');
      return null;
    }
    final user = _webguiUserController.text.trim();
    final pass = _webguiPassController.text;
    if (user.isEmpty || pass.isEmpty) {
      _toast('请填写用户名和密码');
      return null;
    }
    return WebguiSession(baseUrl: address, username: user, password: pass);
  }

  Future<void> _testWebgui() async {
    final session = await _buildWebguiSession();
    if (session == null) return;
    setState(() => _webguiBusy = true);
    try {
      await session.login();
      _toast('登录成功（root 会话已建立）');
    } on WebguiSessionException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _webguiBusy = false);
    }
  }

  Future<void> _saveWebgui() async {
    final session = await _buildWebguiSession();
    if (session == null) return;
    setState(() => _webguiBusy = true);
    try {
      await session.login();
      await _storage.saveWebgui(
          _webguiUserController.text.trim(), _webguiPassController.text);
      _toast('已保存并验证通过');
    } on WebguiSessionException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _webguiBusy = false);
    }
  }

  // -------------------- 主题 / 保存位置 / 缓存 --------------------

  Future<void> _onThemeChanged(int index) async {
    setState(() => _themePresetIndex = index);
    await _storage.saveThemePresetIndex(index);
    ThemeController.apply(ThemePreset.fromIndex(index)); // 立即生效
  }

  Future<void> _onSaveLocationChanged(int location) async {
    if (location == StorageService.saveLocationCustom) {
      // 手动选择目录（走系统目录选择器）
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null || picked.isEmpty) return; // 用户取消
      setState(() {
        _saveLocation = location;
        _saveLocationPath = picked;
      });
      await _storage.saveSaveLocation(location);
      await _storage.saveSaveLocationPath(picked);
      _toast('已选择：$picked');
    } else {
      setState(() => _saveLocation = location);
      await _storage.saveSaveLocation(location);
    }
  }

  Future<void> _onCacheChanged(double value) async {
    setState(() => _cacheLimitMb = value);
    await _storage.saveCacheLimitMb(value.round());
  }

  // -------------------- 工具 --------------------

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 统一尺寸的操作按钮：高度 44、图标 18、文字 13，避免页面内按钮大小不一
  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    Color? color,
    bool busy = false,
  }) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
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
                _buildWebguiCard(),
                const SizedBox(height: 16),
                _buildThemeCard(),
                const SizedBox(height: 16),
                _buildSaveLocationCard(),
                const SizedBox(height: 16),
                _buildCacheCard(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '提示：服务器地址和 WebDAV 地址相互独立，可以指向不同的主机/端口；'
                    '所有配置改动在保存后立即生效，无需重启 App。',
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildConnectionCard() {
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
          _buildSectionTitle(Icons.dns_rounded, '服务器连接'),
          const SizedBox(height: 6),
          Text('可填写多个地址（局域网、外网 HTTPS 都行），App 启动时自动选择当前可达的。',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.5)),
          const SizedBox(height: 14),
          for (var i = 0; i < _addressControllers.length; i++) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressControllers[i],
                    decoration: InputDecoration(
                      hintText: i == 0 ? '例如 192.168.1.10 或 nas.example.com' : '备用地址 ${i + 1}',
                      prefixIcon: const Icon(Icons.router_rounded),
                      suffixIcon: i == 0
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => _removeAddressField(i),
                              tooltip: '移除该地址',
                            ),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addAddressField,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加备用地址'),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              prefixIcon: Icon(Icons.vpn_key_rounded),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.save_rounded,
                  label: '保存并应用',
                  busy: _savingConnection,
                  onPressed: _saveAndApplyConnection,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.wifi_tethering_rounded,
                  label: '重新探测',
                  busy: _probing,
                  onPressed: _reprobe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _actionButton(
              icon: Icons.link_off_rounded,
              label: '断开连接（清除所有配置）',
              color: AppColors.red,
              onPressed: _disconnect,
            ),
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
          _buildSectionTitle(Icons.folder_rounded, 'WebDAV 文件管理'),
          const SizedBox(height: 6),
          Text('OpenList 或其他 WebDAV 服务。地址只填主页地址即可，/dav 会自动补全。',
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
                child: _actionButton(
                  icon: Icons.network_check_rounded,
                  label: '测试',
                  busy: _webdavBusy,
                  onPressed: _testWebdav,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.save_rounded,
                  label: '保存',
                  busy: _webdavBusy,
                  onPressed: _saveWebdav,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.delete_sweep_rounded,
                  label: '清除',
                  color: AppColors.red,
                  onPressed: _clearWebdav,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebguiCard() {
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
          _buildSectionTitle(Icons.power_settings_new_rounded, '系统控制（root 密码）'),
          const SizedBox(height: 6),
          Text(
            '用于 App 内实现整机重启/关机、SMART 明细等 GraphQL 接口没有的能力。'
            '仅当你在 Unraid 里设置了 root 密码（webGUI 可登录）时可用。',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _webguiUserController,
            decoration: const InputDecoration(
              labelText: '用户名（默认 root）',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webguiPassController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.login_rounded,
                  label: '测试登录',
                  busy: _webguiBusy,
                  onPressed: _testWebgui,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  icon: Icons.save_rounded,
                  label: '保存',
                  busy: _webguiBusy,
                  onPressed: _saveWebgui,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard() {
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
          _buildSectionTitle(Icons.palette_rounded, '主题'),          const SizedBox(height: 4),
          for (var i = 0; i < ThemePreset.values.length; i++)
            RadioListTile<int>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.orange,
              title: Text(ThemePreset.values[i].label,
                  style: const TextStyle(fontSize: 14)),
              value: i,
              groupValue: _themePresetIndex,
              onChanged: (v) {
                if (v != null) _onThemeChanged(v);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSaveLocationCard() {
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
          _buildSectionTitle(Icons.save_rounded, '下载保存位置'),
          const SizedBox(height: 4),
          RadioListTile<int>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.orange,
            title: const Text('缓存目录（默认，超限自动清理）', style: TextStyle(fontSize: 14)),
            value: StorageService.saveLocationCache,
            groupValue: _saveLocation,
            onChanged: (v) {
              if (v != null) _onSaveLocationChanged(v);
            },
          ),
          RadioListTile<int>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.orange,
            title: const Text('文档目录（持久保存，不参与清理）', style: TextStyle(fontSize: 14)),
            value: StorageService.saveLocationDocuments,
            groupValue: _saveLocation,
            onChanged: (v) {
              if (v != null) _onSaveLocationChanged(v);
            },
          ),
          RadioListTile<int>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.orange,
            title: const Text('自定义目录（手动选择）', style: TextStyle(fontSize: 14)),
            subtitle: _saveLocationPath == null
                ? null
                : Text(_saveLocationPath!,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textFaint),
                    overflow: TextOverflow.ellipsis),
            value: StorageService.saveLocationCustom,
            groupValue: _saveLocation,
            onChanged: (v) {
              if (v != null) _onSaveLocationChanged(v);
            },
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
          _buildSectionTitle(Icons.sd_storage_rounded, '文件缓存上限'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('超过上限后会自动清理最早的缓存文件。',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textFaint, height: 1.5)),
              ),
              Text(
                _cacheLimitMb >= 1000
                    ? '${(_cacheLimitMb / 1000).toStringAsFixed(1)} GB'
                    : '${_cacheLimitMb.round()} MB',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.orange,
                ),
              ),
            ],
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
            children: [
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
