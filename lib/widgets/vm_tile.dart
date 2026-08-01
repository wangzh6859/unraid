import 'package:flutter/material.dart';
import '../models/vm_domain.dart';
import '../theme/app_theme.dart';

class VmTile extends StatelessWidget {
  final VmDomainInfo vm;
  final bool isBusy;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onReboot;

  const VmTile({
    super.key,
    required this.vm,
    required this.isBusy,
    required this.onStart,
    required this.onStop,
    required this.onPause,
    required this.onResume,
    required this.onReboot,
  });

  Color get _stateColor {
    switch (vm.state) {
      case VmState.running:
        return AppColors.green;
      case VmState.idle:
        return AppColors.blue;
      case VmState.paused:
        return AppColors.yellow;
      case VmState.shutdown:
      case VmState.shutoff:
        return AppColors.textFaint;
      case VmState.crashed:
        return AppColors.red;
      case VmState.pmsuspended:
        return AppColors.yellow;
      case VmState.nostate:
        return AppColors.textFaint;
    }
  }

  String get _stateLabel {
    switch (vm.state) {
      case VmState.running:
        return '运行中';
      case VmState.idle:
        return '空闲';
      case VmState.paused:
        return '已暂停';
      case VmState.shutdown:
        return '关机中';
      case VmState.shutoff:
        return '已关机';
      case VmState.crashed:
        return '已崩溃';
      case VmState.pmsuspended:
        return '已挂起';
      case VmState.nostate:
        return '未知状态';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.dvr_rounded, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: _stateColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(_stateLabel,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            _buildActions(),
        ],
      ),
    );
  }

  Widget _buildActions() {
    switch (vm.state) {
      case VmState.running:
      case VmState.idle:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPause,
              icon: const Icon(Icons.pause_circle_outline_rounded),
              color: AppColors.textSecondary,
              tooltip: '暂停',
            ),
            IconButton(
              onPressed: onReboot,
              icon: const Icon(Icons.restart_alt_rounded),
              color: AppColors.blue,
              tooltip: '重启',
            ),
            IconButton(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
              color: AppColors.red,
              tooltip: '关机',
            ),
          ],
        );
      case VmState.paused:
        return IconButton(
          onPressed: onResume,
          icon: const Icon(Icons.play_circle_outline_rounded),
          color: AppColors.green,
          tooltip: '恢复',
        );
      case VmState.shutdown:
      case VmState.shutoff:
      case VmState.crashed:
      case VmState.pmsuspended:
      case VmState.nostate:
        return IconButton(
          onPressed: onStart,
          icon: const Icon(Icons.play_circle_outline_rounded),
          color: AppColors.green,
          tooltip: '启动',
        );
    }
  }
}
