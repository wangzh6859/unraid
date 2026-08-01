import 'package:flutter/foundation.dart';

enum TransferState { running, done, failed }

/// 一条上传/下载任务（文件管理页的传输记录）。
class TransferTask {
  final String id;
  final String name;
  final bool isUpload;

  double progress; // 0.0 ~ 1.0
  int bytesDone;
  int bytesTotal;
  TransferState state;
  String? error;

  TransferTask({
    required this.id,
    required this.name,
    required this.isUpload,
    this.progress = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.state = TransferState.running,
  });

  String get progressLabel {
    if (bytesTotal <= 0) return '${(progress * 100).toStringAsFixed(0)}%';
    return '${_fmt(bytesDone)} / ${_fmt(bytesTotal)} · ${(progress * 100).toStringAsFixed(0)}%';
  }

  static String _fmt(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }
}

/// 全局传输任务中心（单例）：所有上传/下载都登记到这里，
/// 文件页右上角的"传输任务"按钮展示实时进度。
class TransferManager extends ChangeNotifier {
  TransferManager._();

  static final TransferManager instance = TransferManager._();

  final List<TransferTask> _tasks = [];

  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  bool get hasActive => _tasks.any((t) => t.state == TransferState.running);

  TransferTask start({required String name, required bool isUpload}) {
    final task = TransferTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      isUpload: isUpload,
    );
    _tasks.insert(0, task);
    notifyListeners();
    return task;
  }

  void update(
    TransferTask task, {
    double? progress,
    int? bytesDone,
    int? bytesTotal,
  }) {
    if (progress != null) task.progress = progress;
    if (bytesDone != null) task.bytesDone = bytesDone;
    if (bytesTotal != null) task.bytesTotal = bytesTotal;
    notifyListeners();
  }

  void finish(TransferTask task, {String? error}) {
    task.state = error == null ? TransferState.done : TransferState.failed;
    task.error = error;
    if (error == null) task.progress = 1;
    notifyListeners();
  }

  void clearFinished() {
    _tasks.removeWhere((t) => t.state != TransferState.running);
    notifyListeners();
  }
}
