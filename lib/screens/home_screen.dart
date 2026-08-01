import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'docker_screen.dart';
import 'files_screen.dart';
import 'vm_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  UnraidApi? _api;
  String? _activeAddress;
  bool _probing = true;
  int _filesEpoch = 0; // 从设置页改完 WebDAV 回来后，强制重建文件页
  final _storage = StorageService();
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final saved = await _storage.loadConnection();
    if (!mounted) return;
    if (saved == null) {
      _gotoLogin();
      return;
    }

    // 多地址自动探测：并行尝试所有地址，选第一个可达的；
    // 全部不可达时先用第一个地址，让页面显示具体的连接错误。
    final best = await UnraidApi.probeBestAddress(saved.addresses, saved.apiKey);
    if (!mounted) return;

    final base = best ?? saved.addresses.first;
    setState(() {
      _activeAddress = base;
      _api = UnraidApi(baseUrl: base, apiKey: saved.apiKey);
      _probing = false;
    });
    _checkUpdate();
  }

  void _gotoLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // 从设置页返回：WebDAV 配置可能被修改，强制文件页重新读取
    if (mounted) setState(() => _filesEpoch++);
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService().checkForUpdate();
    if (mounted && info != null) {
      setState(() => _updateInfo = info);
    }
  }

  Future<void> _logout() async {
    await _storage.clear();
    if (!mounted) return;
    _gotoLogin();
  }

  @override
  Widget build(BuildContext context) {
    if (_probing || _api == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                '正在探测可用地址…',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final screens = [
      DashboardScreen(api: _api!),
      DockerScreen(api: _api!),
      VmScreen(api: _api!),
      FilesScreen(
        key: ValueKey('files_$_filesEpoch'),
        onOpenSettings: _openSettings,
      ),
    ];
    const titles = ['仪表盘', 'Docker 容器', '虚拟机', '文件管理'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_rounded),
          tooltip: '设置',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titles[_tabIndex],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (_activeAddress != null)
              Text(
                _activeAddress!.replaceFirst('://', ' · '),
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.textFaint),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: '断开连接',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_tabIndex == 0 && _updateInfo != null) _buildUpdateBanner(_updateInfo!),
          Expanded(child: screens[_tabIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.speed_rounded),
            label: '仪表盘',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.widgets_rounded),
            label: 'Docker',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dvr_rounded),
            label: '虚拟机',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: '文件',
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateBanner(UpdateInfo info) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.gradientPrimary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: Colors.black),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '发现新版本 ${info.latestVersion}，点击下载安装',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication),
            style: TextButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('更新', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
