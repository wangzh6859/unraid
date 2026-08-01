import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/storage_service.dart';
import '../services/transfer_manager.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';

/// 文件管理页（WebDAV / OpenList）。
///
/// - 连接配置在「设置」页里统一维护（地址自动补 /dav）
/// - 右上角：新建/上传（+）与传输任务（⇅）
/// - 支持：浏览 / 新建文件夹 / 上传 / 下载并打开 / 重命名 / 删除
/// - 前台每 2 秒自动刷新；在子目录里按系统返回键回到上级目录
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

  @override
  Widget build(BuildContext context) {
    if (_checkingSaved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_webdav == null) {
      return _NotConfigured(onOpenSettings: widget.onOpenSettings);
    }
    return _FileBrowser(webdav: _webdav!);
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
            Text(
              '还没有配置文件管理',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              '到设置页填写 OpenList（或其他 WebDAV 服务）的地址和账号密码即可，'
              '地址只填 OpenList 主页地址，/dav 会自动补全。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 20),
            // 纯文字居中按钮（图标会破坏水平居中，去掉）
            ElevatedButton(
              onPressed: onOpenSettings,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: const Text('去设置'),
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
  const _FileBrowser({required this.webdav});

  @override
  State<_FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<_FileBrowser> {
  final _storage = StorageService();
  String _path = '/';
  List<WebdavEntry> _entries = [];
  bool _loading = true;
  bool _transferActive = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // 前台每 2 秒静默刷新当前目录（传输过程中暂停，避免列表跳动）
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  Future<void> _silentRefresh() async {
    if (_loading || _transferActive) return;
    try {
      final list = await widget.webdav.listDir(_path);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _error = null;
      });
    } catch (_) {}
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
    final task = TransferManager.instance.start(name: file.name, isUpload: true);
    _transferActive = true;
    try {
      await widget.webdav.uploadFromFile(
        File(localPath),
        remotePath,
        onProgress: (count, total) {
          TransferManager.instance.update(
            task,
            bytesDone: count.toInt(),
            bytesTotal: total.toInt(),
            progress: total > 0 ? count / total : 0,
          );
        },
      );
      TransferManager.instance.finish(task);
      _snack('上传完成');
      _load();
    } on WebdavException catch (e) {
      TransferManager.instance.finish(task, error: e.message);
      _snack(e.message);
    } catch (e) {
      TransferManager.instance.finish(task, error: '$e');
      _snack('上传失败：$e');
    } finally {
      _transferActive = false;
    }
  }

  Future<void> _downloadAndOpen(WebdavEntry entry) async {
    final task = TransferManager.instance.start(name: entry.name, isUpload: false);
    _transferActive = true;
    final location = await _storage.loadSaveLocation();
    final customPath = await _storage.loadSaveLocationPath();
    String? localPath;
    try {
      localPath = await widget.webdav.downloadToLocal(
        entry.path,
        entry.name,
        location: location,
        customPath: customPath,
        onProgress: (count, total) {
          TransferManager.instance.update(
            task,
            bytesDone: count.toInt(),
            bytesTotal: total.toInt(),
            progress: total > 0 ? count / total : 0,
          );
        },
      );
      TransferManager.instance.finish(task);
    } on WebdavException catch (e) {
      TransferManager.instance.finish(task, error: e.message);
      _snack(e.message);
      _transferActive = false;
      return;
    } catch (e) {
      TransferManager.instance.finish(task, error: '$e');
      _snack('下载失败：$e');
      _transferActive = false;
      return;
    }
    _transferActive = false;

    // 预览/缓存文件统一放在保存目录的 temp 子目录，按"缓存上限"清理旧文件
    final limitMb = await _storage.loadCacheLimitMb();
    await widget.webdav.cleanupCache(limitMb,
        location: location, customPath: customPath);

    if (!mounted) return;
    final result = await OpenFilex.open(localPath);
    if (result.type != ResultType.done) {
      _snack('文件已保存到本地（$localPath）');
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

    final parent = _path == '/' ? '' : _path;
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

  // -------------------- 传输任务 --------------------

  void _showTransfers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => ListenableBuilder(
        listenable: TransferManager.instance,
        builder: (_, __) {
          final tasks = TransferManager.instance.tasks;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '传输任务',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (tasks.isNotEmpty)
                        TextButton(
                          onPressed: TransferManager.instance.clearFinished,
                          child: const Text('清除已完成', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无传输任务',
                          style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final t = tasks[i];
                          return _buildTransferTile(t);
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransferTile(TransferTask t) {
    final color = switch (t.state) {
      TransferState.running => AppColors.orange,
      TransferState.done => AppColors.green,
      TransferState.failed => AppColors.red,
    };
    final label = switch (t.state) {
      TransferState.running => (t.isUpload ? '上传中' : '下载中'),
      TransferState.done => '已完成',
      TransferState.failed => '失败',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                t.isUpload ? Icons.upload_rounded : Icons.download_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: t.state == TransferState.done ? 1 : t.progress,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.error ?? t.progressLabel,
            style: TextStyle(fontSize: 11, color: AppColors.textFaint),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    // 系统返回键：在子目录时返回上级，根目录时才退出 App
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_atRoot) _goUp();
      },
      child: Column(
        children: [
          // 顶部工具条：路径 + 右上角（传输任务、新建/上传）
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                if (!_atRoot)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: _goUp,
                    tooltip: '返回上级',
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    _atRoot ? '/' : _path,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_vert_rounded),
                  onPressed: _showTransfers,
                  tooltip: '传输任务',
                  color: AppColors.textSecondary,
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.add_rounded, color: AppColors.orange),
                  tooltip: '新建/上传',
                  onSelected: (v) {
                    if (v == 'mkdir') _createFolder();
                    if (v == 'upload') _uploadFile();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'mkdir', child: Text('新建文件夹')),
                    PopupMenuItem(value: 'upload', child: Text('上传文件')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: AppColors.textFaint),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text('这个文件夹是空的',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.orange,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
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
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              subtitle: entry.isDir
                  ? null
                  : Text(entry.sizeLabel,
                      style: TextStyle(
                          color: AppColors.textFaint, fontSize: 12)),
              trailing: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
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
