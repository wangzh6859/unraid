import 'package:flutter/material.dart';
import '../models/system_stats.dart';
import '../theme/app_theme.dart';

class DiskDetailScreen extends StatelessWidget {
  final ArrayDiskInfo disk;
  const DiskDetailScreen({super.key, required this.disk});

  Color get _runStateColor {
    if (!disk.isMounted) return AppColors.textFaint;
    if (disk.isSpinning == null) return AppColors.textFaint;
    return disk.isSpinning! ? AppColors.green : AppColors.yellow;
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            '提示：官方 Unraid API 目前只提供粗粒度的 SMART 状态（正常/未知），暂不提供详细的 SMART 原始属性表（比如通电时长、重映射扇区数等）。',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.5),
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
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
