import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../services/update_service.dart';
import '../services/webgui_session.dart';
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
  ({String username, String password})? _webgui;

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
    final wg = await _storage.loadWebgui();
    if (mounted) setState(() => _webgui = wg);
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
    // 从设置页返回：连接配置 / WebDAV 配置都可能被修改，
    // 重新加载连接（重新探测当前地址）并强制文件页重建。
    if (!mounted) return;
    setState(() => _filesEpoch++);
    await _init();
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService().checkForUpdate();
    if (mounted && info != null) {
      setState(() => _updateInfo = info);
    }
  }

  // -------------------- 系统电源控制（webGUI 会话）--------------------

  Future<void> _confirmPower(String cmd, String title, String desc) async {
    final wg = _webgui;
    final api = _api;
    if (wg == null || api == null) return;
    final ok = await _countdownConfirm(title, desc);
    if (!ok || !mounted) return;
    try {
      final session = WebguiSession(
        baseUrl: api.baseUrl,
        username: wg.username,
        password: wg.password,
      );
      await session.sendBootCommand(cmd);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(cmd == 'reboot'
              ? '重启命令已发送，服务器即将重启'
              : '关机命令已发送，服务器即将关机'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  /// 倒计时确认：默认 10 秒后自动执行，期间可取消
  Future<bool> _countdownConfirm(String title, String desc) {
    final completer = Completer<bool>();
    // 先捕获 Navigator：即使等待期间页面被销毁，倒计时结束也能正常关掉对话框
    final navigator = Navigator.of(context);
    var seconds = 10;
    late StateSetter dialogSetState;
    Timer? timer;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          dialogSetState = setState;
          return AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            title: Text(title),
            content: Text('$desc\n\n$seconds 秒后自动执行，可点取消'),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  completer.complete(false);
                  Navigator.pop(ctx);
                },
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      seconds--;
      dialogSetState(() {});
      if (seconds <= 0) {
        t.cancel();
        completer.complete(true);
        navigator.pop();
      }
    });
    return completer.future;
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
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                style: TextStyle(
                    fontSize: 10.5, color: AppColors.textFaint),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // 首页（仪表盘）右上角：整机重启/关机（需设置页配置 root 密码）
          if (_tabIndex == 0 && _webgui != null) ...[
            IconButton(
              onPressed: () => _confirmPower(
                  'reboot', '重启 NAS？', '服务器将重启，所有服务会短暂中断。'),
              icon: const Icon(Icons.restart_alt_rounded),
              color: AppColors.blue,
              tooltip: '重启 NAS',
            ),
            IconButton(
              onPressed: () => _confirmPower(
                  'powerdown', '关机 NAS？', '服务器将完全关机，需手动开机。'),
              icon: const Icon(Icons.power_settings_new_rounded),
              color: AppColors.red,
              tooltip: '关机',
            ),
          ],
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
