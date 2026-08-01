import 'package:flutter/material.dart';

import '../models/system_stats.dart';
import '../services/storage_service.dart';
import '../services/webgui_session.dart';
import '../theme/app_theme.dart';

/// 磁盘详情页：健康 / SMART / 温度 / 容量 / 硬件信息。
/// SMART 完整属性表通过 webGUI 会话（root 密码）从旧版页面抓取。
class DiskDetailScreen extends StatefulWidget {
  final ArrayDiskInfo disk;
  final String baseUrl;

  const DiskDetailScreen({
    super.key,
    required this.disk,
    required this.baseUrl,
  });

  @override
  State<DiskDetailScreen> createState() => _DiskDetailScreenState();
}

class _DiskDetailScreenState extends State<DiskDetailScreen> {
  List<SmartAttribute>? _smart;
  String? _smartError;
  bool _smartLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSmart();
  }

  Future<void> _loadSmart() async {
    final creds = await StorageService().loadWebgui();
    if (!mounted) return;
    if (creds == null) {
      setState(() => _smartError = '未配置系统登录（设置页 → 系统控制），无法获取 SMART 明细');
      return;
    }
    setState(() => _smartLoading = true);
    try {
      final session = WebguiSession(
        baseUrl: widget.baseUrl,
        username: creds.username,
        password: creds.password,
      );
      final device = widget.disk.device.replaceAll('/dev/', '');
      final html = await session.fetchSmartPage(device);
      final attrs = parseSmartAttributes(html);
      if (!mounted) return;
      setState(() {
        _smart = attrs.isEmpty ? null : attrs;
        if (attrs.isEmpty) {
          final preview = html
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          _smartError = 'SMART 页面格式无法解析。页面内容预览：'
              '${preview.length > 160 ? preview.substring(0, 160) : preview}';
        }
        _smartLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _smartError = '$e';
        _smartLoading = false;
      });
    }
  }

  Color get _runStateColor {
    if (!widget.disk.isMounted) return AppColors.textFaint;
    if (widget.disk.isSpinning == null) return AppColors.textFaint;
    return widget.disk.isSpinning! ? AppColors.green : AppColors.yellow;
  }

  @override
  Widget build(BuildContext context) {
    final disk = widget.disk;
    return Scaffold(
      appBar: AppBar(title: Text(disk.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------- 状态总览 -------
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.storage_rounded,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(disk.device.isNotEmpty ? disk.device : '未知设备路径',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(_typeLabel(disk.type),
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _pill('健康', disk.healthLabel,
                        disk.isHealthy ? AppColors.green : AppColors.red),
                    const SizedBox(width: 10),
                    _pill('运行状态', disk.runStateLabel, _runStateColor),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _pill(
                        'SMART',
                        disk.smartLabel,
                        disk.smartStatus == 'OK'
                            ? AppColors.green
                            : AppColors.textFaint),
                    const SizedBox(width: 10),
                    if (disk.tempC != null)
                      _pill('温度', '${disk.tempC}°C', AppColors.orange),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ------- 容量 -------
          if (disk.fsSizeKb > 0) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('存储空间',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: disk.usedPercent / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('已用 ${disk.usedLabel} / 共 ${disk.totalLabel}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ------- 硬件信息 -------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _infoRow('厂商', disk.vendor),
                _infoRow('接口类型', disk.interfaceType),
                _infoRow('序列号', disk.serialNum),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ------- SMART 完整属性（webGUI 会话抓取）-------
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('SMART 属性',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    if (_smartLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_smartLoading && _smart == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('正在获取 SMART 数据…',
                          style: TextStyle(
                              color: AppColors.textFaint, fontSize: 13)),
                    ),
                  )
                else if (_smartError != null && _smart == null)
                  Text(_smartError!,
                      style: TextStyle(
                          color: AppColors.textFaint, fontSize: 12, height: 1.5))
                else if (_smart != null)
                  ..._smart!.map((a) => _smartRow(a)),
                const SizedBox(height: 8),
                Text(
                  'SMART 明细通过设置页配置的 root 密码（webGUI 会话）抓取；'
                  '未配置或磁盘休眠时可能获取不到。',
                  style: TextStyle(
                      color: AppColors.textFaint, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smartRow(SmartAttribute a) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '值 ${a.value} · 最差 ${a.worst} · 阈值 ${a.threshold}',
                  style:
                      TextStyle(color: AppColors.textFaint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              a.rawValue,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'PARITY':
        return '校验盘';
      case 'CACHE':
        return '缓存盘';
      case 'BOOT':
        return '启动盘';
      case 'FLASH':
        return 'U盘(Flash)';
      default:
        return '数据盘';
    }
  }

  Widget _pill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              (value == null || value.isEmpty) ? '未知' : value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
