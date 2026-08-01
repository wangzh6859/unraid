import 'package:flutter/material.dart';
import '../models/docker_container.dart';
import '../theme/app_theme.dart';

class ContainerTile extends StatelessWidget {
  final DockerContainerInfo container;
  final bool isBusy;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onUnpause;

  const ContainerTile({
    super.key,
    required this.container,
    required this.isBusy,
    required this.onStart,
    required this.onStop,
    required this.onPause,
    required this.onUnpause,
  });

  Color get _stateColor {
    switch (container.state) {
      case ContainerState.running:
        return AppColors.green;
      case ContainerState.paused:
        return AppColors.yellow;
      case ContainerState.exited:
        return AppColors.textFaint;
      case ContainerState.unknown:
        return AppColors.red;
    }
  }

  String get _stateLabel {
    switch (container.state) {
      case ContainerState.running:
        return '运行中';
      case ContainerState.paused:
        return '已暂停';
      case ContainerState.exited:
        return '已停止';
      case ContainerState.unknown:
        return '未知';
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
            child: container.iconUrl != null && container.iconUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      container.iconUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.widgets_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : const Icon(Icons.widgets_rounded,
                    color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  container.name,
                  style: const TextStyle(
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
                      decoration: BoxDecoration(
                        color: _stateColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _stateLabel,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isBusy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    switch (container.state) {
      case ContainerState.running:
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
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
              color: AppColors.red,
              tooltip: '停止',
            ),
          ],
        );
      case ContainerState.paused:
        return IconButton(
          onPressed: onUnpause,
          icon: const Icon(Icons.play_circle_outline_rounded),
          color: AppColors.green,
          tooltip: '恢复',
        );
      case ContainerState.exited:
      case ContainerState.unknown:
        return IconButton(
          onPressed: onStart,
          icon: const Icon(Icons.play_circle_outline_rounded),
          color: AppColors.green,
          tooltip: '启动',
        );
    }
  }
}
