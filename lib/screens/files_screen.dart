import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/storage_service.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';

/// 文件管理页（WebDAV / OpenList）。
///
/// - 连接配置在「设置」页里统一维护（地址自动补 /dav）
/// - 未配置时提示去设置页
/// - 支持：浏览 / 新建文件夹 / 上传 / 下载并打开 / 重命名 / 删除
class FilesScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const FilesScreen({super.key, required this.onOpenSettings});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _storage = StorageService();
  WebdavService? _webdav;
  bool _checkingSaved = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final creds = await _storage.loadWebdav();
    if (creds != null && mounted) {
      setState(() => _webdav = WebdavService(creds));
    }
    if (mounted) setState(() => _checkingSaved = false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('退出登录？'),
        content: const Text('会清除本地保存的 WebDAV 地址和密码，下次要重新输入。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.clearWebdav();
    if (mounted) setState(() => _webdav = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSaved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_webdav == null) {
      return _NotConfigured(onOpenSettings: widget.onOpenSettings);
    }
    return _FileBrowser(webdav: _webdav!, onLogout: _logout);
  }
}

// ============================== 未配置提示 ==============================

class _NotConfigured extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _NotConfigured({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.gradientTeal,
                borderRadius: BorderRadius.circular(18),
              ),
              child:
                  const Icon(Icons.folder_rounded, color: Colors.black, size: 30),
            ),
            const SizedBox(height: 20),
            const Text(
              '还没有配置文件管理',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              '到设置页填写 OpenList（或其他 WebDAV 服务）的地址和账号密码即可，'
              '地址只填 OpenList 主页地址，/dav 会自动补全。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================== 文件浏览器 ==============================

class _FileBrowser extends StatefulWidget {
  final WebdavService webdav;
  final VoidCallback onLogout;
  const _FileBrowser({required this.webdav, required this.onLogout});

  @override
  State<_FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<_FileBrowser> {
  final _storage = StorageService();
  String _path = '/';
  List<WebdavEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.webdav.listDir(_path);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } on WebdavException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  void _enterFolder(WebdavEntry entry) {
    setState(() => _path = entry.path);
    _load();
  }

  bool get _atRoot => _path == '/' || _path.isEmpty;

  void _goUp() {
    if (_atRoot) return;
    final trimmed =
        _path.endsWith('/') ? _path.substring(0, _path.length - 1) : _path;
    final idx = trimmed.lastIndexOf('/');
    setState(() => _path = idx <= 0 ? '/' : trimmed.substring(0, idx));
    _load();
  }

  String _joinPath(String name) {
    final n = name.startsWith('/') ? name.substring(1) : name;
    return _atRoot ? '/$n' : '$_path/$n';
  }

  IconData _iconFor(WebdavEntry entry) {
    if (entry.isDir) return Icons.folder_rounded;
    switch (entry.kind) {
      case WebdavFileKind.image:
        return Icons.image_rounded;
      case WebdavFileKind.video:
        return Icons.movie_rounded;
      case WebdavFileKind.text:
        return Icons.description_rounded;
      case WebdavFileKind.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  // -------------------- 操作：新建 / 上传 / 下载 / 重命名 / 删除 --------------------

  Future<void> _showFabs() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded,
                  color: AppColors.orange),
              title: const Text('新建文件夹'),
              onTap: () => Navigator.pop(ctx, 'mkdir'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded,
                  color: AppColors.orange),
              title: const Text('上传文件'),
              onTap: () => Navigator.pop(ctx, 'upload'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'mkdir') {
      await _createFolder();
    } else if (action == 'upload') {
      await _uploadFile();
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.webdav.createFolder(_joinPath(name));
      _load();
    } on WebdavException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final localPath = file.path;
    if (localPath == null) {
      _snack('无法读取所选文件');
      return;
    }

    final remotePath = _joinPath(file.name);
    var done = false;
    await _runWithProgress('上传 ${file.name}', (onProgress) async {
      await widget.webdav.uploadFromFile(
        File(localPath),
        remotePath,
        onProgress: onProgress,
      );
      done = true;
    });
    if (done) {
      _snack('上传完成');
      _load();
    }
  }

  Future<void> _downloadAndOpen(WebdavEntry entry) async {
    String? localPath;
    var done = false;
    await _runWithProgress('下载 ${entry.name}', (onProgress) async {
      localPath = await widget.webdav
          .downloadToCache(entry.path, entry.name, onProgress: onProgress);
      done = true;
    });
    if (!done || localPath == null) return;
    final savedPath = localPath!; // 闭包内赋值的变量不会被类型提升，用 ! 显式解包

    // 按设置里的缓存上限清理旧文件
    final limitMb = await _storage.loadCacheLimitMb();
    await widget.webdav.cleanupCache(limitMb);

    if (!mounted) return;
    final result = await OpenFilex.open(savedPath);
    if (result.type != ResultType.done) {
      _snack('文件已保存到本地缓存目录');
    }
  }

  Future<void> _renameEntry(WebdavEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == entry.name) return;

    final parent = _path == '/'
        ? ''
        : _path;
    try {
      await widget.webdav.rename(
        entry.path,
        '$parent/$newName',
        isDir: entry.isDir,
      );
      _load();
    } on WebdavException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _deleteEntry(WebdavEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(entry.isDir ? '删除文件夹？' : '删除文件？'),
        content: Text('「${entry.name}」将被永久删除，此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.webdav.delete(entry.path, isDir: entry.isDir);
      _snack('已删除');
      _load();
    } on WebdavException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _handleAction(WebdavEntry entry, String action) async {
    switch (action) {
      case 'open':
        await _downloadAndOpen(entry);
        break;
      case 'rename':
        await _renameEntry(entry);
        break;
      case 'delete':
        await _deleteEntry(entry);
        break;
    }
  }

  /// 带进度条的对话框；[run] 在对话框展示期间执行，通过 onProgress 更新进度。
  Future<void> _runWithProgress(
    String title,
    Future<void> Function(void Function(double p) onProgress) run,
  ) async {
    // 先捕获根 Navigator：即使操作期间用户切走了 Tab 导致本页 dispose，
    // 对话框也能正常关闭，不会卡在屏幕上。
    final navigator = Navigator.of(context);
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: v,
                backgroundColor: AppColors.border,
                color: AppColors.orange,
              ),
              const SizedBox(height: 10),
              Text('${(v * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    try {
      await run((p) => progress.value = p);
    } on WebdavException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      progress.dispose();
      if (navigator.canPop()) navigator.pop();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 路径导航条（替代原来的内嵌 AppBar）
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              if (!_atRoot)
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: _goUp,
                  tooltip: '返回上级',
                )
              else
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: widget.onLogout,
                  tooltip: '退出登录',
                ),
              Expanded(
                child: Text(
                  _atRoot ? '/' : _path,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 48, color: AppColors.textFaint),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text('这个文件夹是空的',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.orange,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
        itemCount: _entries.length,
        itemBuilder: (context, i) {
          final entry = _entries[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: ListTile(
              onTap: entry.isDir
                  ? () => _enterFolder(entry)
                  : () => _downloadAndOpen(entry),
              leading: Icon(_iconFor(entry),
                  color: entry.isDir ? AppColors.orange : AppColors.textSecondary),
              title: Text(entry.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              subtitle: entry.isDir
                  ? null
                  : Text(entry.sizeLabel,
                      style: const TextStyle(
                          color: AppColors.textFaint, fontSize: 12)),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textFaint),
                onSelected: (v) => _handleAction(entry, v),
                itemBuilder: (_) => [
                  if (!entry.isDir)
                    const PopupMenuItem(
                        value: 'open', child: Text('下载并打开')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除',
                          style: TextStyle(color: AppColors.red))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
