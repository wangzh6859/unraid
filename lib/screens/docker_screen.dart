import 'package:flutter/material.dart';
import '../models/docker_container.dart';
import '../services/unraid_api.dart';
import '../theme/app_theme.dart';
import '../widgets/container_tile.dart';

class DockerScreen extends StatefulWidget {
  final UnraidApi api;
  const DockerScreen({super.key, required this.api});

  @override
  State<DockerScreen> createState() => _DockerScreenState();
}

class _DockerScreenState extends State<DockerScreen> {
  List<DockerContainerInfo> _containers = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = {};

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
      final list = await widget.api.fetchContainers();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _containers = list;
        _loading = false;
      });
    } on UnraidApiException catch (e) {
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

  Future<void> _runAction(
      String id, Future<void> Function(String) action) async {
    setState(() => _busyIds.add(id));
    try {
      await action(id);
      await _load();
    } on UnraidApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _containers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _containers.isEmpty) {
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

    if (_containers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.widgets_outlined, size: 48, color: AppColors.textFaint),
            SizedBox(height: 12),
            Text('还没有 Docker 容器', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final running = _containers.where((c) => c.state == ContainerState.running).length;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.orange,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '共 ${_containers.length} 个容器 · $running 个运行中',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          ..._containers.map((c) => ContainerTile(
                container: c,
                isBusy: _busyIds.contains(c.id),
                onStart: () => _runAction(c.id, widget.api.startContainer),
                onStop: () => _runAction(c.id, widget.api.stopContainer),
                onPause: () => _runAction(c.id, widget.api.pauseContainer),
                onUnpause: () => _runAction(c.id, widget.api.unpauseContainer),
              )),
        ],
      ),
    );
  }
}
