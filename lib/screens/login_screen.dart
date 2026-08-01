import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// 登录页：填写 API Key + 一个或多个服务器地址。
///
/// 支持多个地址（局域网 http / 外网 https 都填进去），连接时并行探测，
/// 自动使用第一个可达的地址；连接成功后所有地址都会保存，
/// 之后每次打开 App 都会自动重新探测当前可用地址。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final List<TextEditingController> _addressControllers = [
    TextEditingController(),
  ];
  final _apiKeyController = TextEditingController();
  final _storage = StorageService();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    for (final c in _addressControllers) {
      c.dispose();
    }
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final saved = await _storage.loadConnection();
    if (saved != null && mounted) {
      setState(() {
        _apiKeyController.text = saved.apiKey;
        // 已保存的地址回填到输入框（第一个用现有 controller，其余追加）
        for (var i = 0; i < saved.addresses.length; i++) {
          if (i < _addressControllers.length) {
            _addressControllers[i].text = saved.addresses[i];
          } else {
            final c = TextEditingController(text: saved.addresses[i]);
            _addressControllers.add(c);
          }
        }
      });
    }
  }

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

  Future<void> _connect() async {
    final addresses = _addressControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .map(UnraidApi.normalizeAddress)
        .toList();
    final apiKey = _apiKeyController.text.trim();

    if (addresses.isEmpty || apiKey.isEmpty) {
      setState(() => _error = '请至少填写一个 NAS 地址和 API Key');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // 并行探测所有地址，按填写顺序取第一个可达的
    final best = await UnraidApi.probeBestAddress(addresses, apiKey);
    if (!mounted) return;

    if (best == null) {
      setState(() {
        _loading = false;
        _error = '所有地址都无法连接，请检查：\n'
            '· 地址/端口是否正确\n'
            '· 手机和 NAS 网络是否互通\n'
            '· API Key 是否有效\n'
            '· 是否已开启 GraphQL（Settings → Management Access）';
      });
      return;
    }

    await _storage.saveConnection(apiKey: apiKey, addresses: addresses);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPrimary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.dns_rounded,
                    color: Colors.black, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                '连接你的 Unraid',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '在 Unraid WebGUI 的 设置 → Management Access → API Keys 中生成密钥。'
                '\n可填写多个地址（局域网、外网 HTTPS 都行），App 会自动选择当前可达的。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              Text(
                '服务器地址',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _addressControllers.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addressControllers[i],
                        decoration: InputDecoration(
                          hintText: i == 0
                              ? '例如 192.168.1.10 或 nas.example.com'
                              : '备用地址 ${i + 1}',
                          prefixIcon: const Icon(Icons.router_rounded),
                          suffixIcon: i == 0
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
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
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                ),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _connect,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.black,
                          ),
                        )
                      : const Text('连接'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '提示：地址不用带 https:// 或 http:// 前缀，App 会自动补全；'
                '按优先级排序，局域网地址放在最上面会优先使用。',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
