import 'dart:async';

import 'package:flutter/material.dart';

import '../models/system_stats.dart';
import '../models/network_metrics.dart';
import '../services/storage_service.dart';
import '../services/unraid_api.dart';
import '../services/webgui_session.dart';
import '../theme/app_theme.dart';
import '../widgets/usage_ring.dart';
import 'disk_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final UnraidApi api;

  const DashboardScreen({
    super.key,
    required this.api,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 四个独立数据域，各自加载、各自容错：一个失败不影响其他区域
  SystemInfoSnapshot? _info;
  ArraySnapshot? _array;
  MetricsSnapshot? _metrics;
  List<NetworkRateInfo>? _rates;
  List<TemperatureSensor>? _temps;
  List<GpuInfo>? _gpu;
  ({String username, String password})? _webgui;

  String? _errInfo;
  String? _errArray;
  String? _errMetrics;

  // 实时网速：优先 metrics.network（新版本）；不支持时回退到 nchan 频道抓取
  bool _netSupported = true;
  int _netFailures = 0;
  bool _nchanSupported = true;
  int _nchanFailures = 0;

  // 温度传感器（metrics.temperature）：同样做能力检测
  bool _tempSupported = true;
  int _tempFailures = 0;

  bool _initialLoading = true;
  bool _arrayBusy = false;
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
    // 前台每 2 秒刷新实时数据（CPU/内存/网速/磁盘温度），
    // 系统信息（主机名/CPU 型号等静态内容）由下拉刷新更新
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshLive());
    _loadWebgui();
  }

  Future<void> _loadWebgui() async {
    final wg = await StorageService().loadWebgui();
    if (mounted) setState(() => _webgui = wg);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 返回 (结果, 错误信息)，任何异常都不会抛出。
  Future<(T?, String?)> _guard<T>(Future<T> Function() fn) async {
    try {
      return (await fn(), null);
    } on UnraidApiException catch (e) {
      return (null, e.message);
    } catch (e) {
      return (null, '加载失败：$e');
    }
  }

  /// 网络速率：优先 metrics.network，不支持时回退 nchan 频道（需系统登录）
  Future<List<NetworkRateInfo>?> _fetchRatesWithFallback() async {
    if (_netSupported) {
      final r = await _guard(() => widget.api.fetchNetworkRates());
      if (r.$1 != null) {
        _netFailures = 0;
        return r.$1;
      }
      _netFailures++;
      if (_netFailures >= 2) {
        _netSupported = false; // 该 Unraid 版本没有 metrics.network
      }
      return null;
    }
    if (_webgui != null && _nchanSupported) {
      final r = await _guard(() => _fetchNchanRates());
      if (r.$1 != null) {
        _nchanFailures = 0;
        return r.$1;
      }
      _nchanFailures++;
      if (_nchanFailures >= 2) {
        _nchanSupported = false;
      }
    }
    return null;
  }

  Future<List<NetworkRateInfo>> _fetchNchanRates() async {
    final wg = _webgui;
    if (wg == null) throw UnraidApiException('未配置系统登录');
    final session = WebguiSession(
      baseUrl: widget.api.baseUrl,
      username: wg.username,
      password: wg.password,
    );
    return session.fetchNchanNetworkRates();
  }

  Future<void> _loadAll() async {
    setState(() {
      _initialLoading = _info == null && _array == null && _metrics == null;
    });

    // 所有查询并行发起，避免串行等待拖慢加载
    final fInfo = _guard(() => widget.api.fetchSystemInfo());
    final fArray = _guard(() => widget.api.fetchArraySnapshot());
    final fMetrics = _guard(() => widget.api.fetchMetricsSnapshot());
    final fGpu = _guard(() => widget.api.fetchGpus());
    final fTemps = _tempSupported
        ? _guard(() => widget.api.fetchTemperatureSensors())
        : Future.value((null, null));
    final fRates = (_netSupported || (_webgui != null && _nchanSupported))
        ? _fetchRatesWithFallback()
        : Future.value(null);

    final (info, infoErr) = await fInfo;
    final (array, arrayErr) = await fArray;
    final (metrics, metricsErr) = await fMetrics;
    final (gpu, _) = await fGpu;
    final (temps, _) = await fTemps;
    final rates = await fRates;

    if (!mounted) return;
    setState(() {
      if (info != null) _info = info;
      if (array != null) _array = array;
      if (metrics != null) _metrics = metrics;
      if (gpu != null) _gpu = gpu;
      if (temps != null) _temps = temps;
      if (rates != null) _rates = rates;
      _errInfo = infoErr;
      _errArray = arrayErr;
      _errMetrics = metricsErr;
      _initialLoading = false;
    });
  }

  /// 静默刷新实时指标（失败不打扰用户，保留旧数据）
  Future<void> _refreshLive() async {
    _tick++;
    // 并行发起所有实时查询
    final fMetrics = _guard(() => widget.api.fetchMetricsSnapshot());
    final fRates = (_netSupported || (_webgui != null && _nchanSupported))
        ? _fetchRatesWithFallback()
        : Future.value(null);
    final fTemps = _tempSupported
        ? _guard(() => widget.api.fetchTemperatureSensors())
        : Future.value((null, null));
    final fArray = _tick % 2 == 0
        ? _guard(() => widget.api.fetchArraySnapshot())
        : Future.value((null, null));

    final (metrics, _) = await fMetrics;
    final rates = await fRates;
    final (temps, _) = await fTemps;
    final (array, _) = await fArray;

    if (!mounted) return;
    setState(() {
      if (metrics != null) _metrics = metrics;
      if (rates != null) _rates = rates;
      if (array != null) _array = array;
      if (temps != null) _temps = temps;
    });
  }

  Color _arrayColor(String state) {
    switch (state) {
      case 'STARTED':
        return AppColors.green;
      case 'STOPPED':
        return AppColors.textFaint;
      default:
        return AppColors.yellow;
    }
  }

  String _arrayLabel(String state) {
    switch (state) {
      case 'STARTED':
        return '运行中';
      case 'STOPPED':
        return '已停止';
      case 'NEW_ARRAY':
        return '新阵列';
      default:
        return state;
    }
  }

  Future<void> _toggleArray(bool start) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(start ? '启动阵列？' : '停止阵列？'),
        content: Text(
          start
              ? '这会挂载所有磁盘并启动阵列。'
              : '停止阵列会先停掉所有 Docker 容器和虚拟机，确认要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(start ? '启动' : '停止',
                style: TextStyle(color: start ? AppColors.green : AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _arrayBusy = true);
    try {
      await widget.api.setArrayState(start);
      await _loadAll();
    } on UnraidApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _arrayBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 全部区域都失败 → 整页错误 + 重试
    if (_info == null && _array == null && _metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: AppColors.textFaint),
              const SizedBox(height: 12),
              Text(
                _errInfo ?? _errArray ?? _errMetrics ?? '加载失败',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadAll, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.orange,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------- 顶部：主机名 + 系统版本 + 运行时间 -------
          if (_info != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: AppColors.gradientPrimary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.dns_rounded,
                        color: Colors.black, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _info!.hostname,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _info!.distro,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timelapse_rounded,
                                size: 15, color: Colors.black87),
                            const SizedBox(height: 2),
                            Text(
                              _info!.uptimeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (_errInfo != null) _buildSectionError(_errInfo!),

          const SizedBox(height: 16),

          // ------- 阵列状态 + 启停控制 -------
          if (_array != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _arrayColor(_array!.arrayState),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '磁盘阵列 · ${_arrayLabel(_array!.arrayState)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_arrayBusy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  else if (_array!.arrayState == 'STARTED')
                    TextButton.icon(
                      onPressed: () => _toggleArray(false),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('停止'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.red),
                    )
                  else if (_array!.arrayState == 'STOPPED')
                    TextButton.icon(
                      onPressed: () => _toggleArray(true),
                      icon: const Icon(Icons.play_circle_outline_rounded,
                          size: 18),
                      label: const Text('启动'),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.green),
                    ),
                ],
              ),
            ),
          if (_errArray != null) _buildSectionError(_errArray!),

          const SizedBox(height: 16),

          // ------- CPU / 内存 环形使用率 -------
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      UsageRing(
                        label: 'CPU',
                        percent: _metrics?.cpuPercent ?? 0,
                        color: AppColors.orange,
                        centerLabel: _info != null
                            ? '${_info!.cpuCores}核${_info!.cpuThreads}线程'
                            : '',
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          _info?.cpuBrand.isNotEmpty == true
                              ? _info!.cpuBrand
                              : '未知处理器',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _cpuTempAndSpeedLabel(),
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textFaint),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      UsageRing(
                        label: '内存',
                        percent: _metrics?.memPercent ?? 0,
                        color: AppColors.teal,
                        centerLabel: '',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _metrics == null
                            ? '--'
                            : '${_metrics!.memUsedLabel} / ${_metrics!.memTotalLabel}',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textFaint),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_errMetrics != null) _buildSectionError(_errMetrics!),

          // ------- GPU（静态信息 + lm-sensors 温度）-------
          if ((_gpu?.isNotEmpty ?? false) || _gpuTempC != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.memory_rounded,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _gpu != null && _gpu!.isNotEmpty
                          ? _gpu!.map((g) => g.label).join(' / ')
                          : 'GPU',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_gpuTempC != null)
                    Text('${_gpuTempC!.toStringAsFixed(0)}°C',
                        style: TextStyle(
                            color: AppColors.orange,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5)),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ------- 存储空间（含磁盘明细）-------
          if (_array != null && _array!.capacity.totalKb > 0)
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
                      Icon(Icons.sd_storage_rounded,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text('存储空间',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      Text(
                          '${_array!.capacity.usedPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _array!.capacity.usedPercent / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已用 ${_array!.capacity.usedLabel} / 共 ${_array!.capacity.totalLabel}',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textFaint),
                  ),
                  if (_array!.disks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Divider(color: AppColors.border, height: 20),
                    ..._array!.disks.map((d) => _buildDiskRow(d)),
                  ],
                ],
              ),
            ),

          // ------- 网络：实时速率（不支持时退回静态网卡信息）-------
          if (_rates != null || (_info?.networkInterfaces.isNotEmpty ?? false)) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text('网络',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                if (_rates != null)
                  Tooltip(
                    message: '每 2 秒自动刷新',
                    child: Icon(Icons.info_outline_rounded,
                        size: 15, color: AppColors.textFaint),
                  ),
                const Spacer(),
                if (_rates != null)
                  Text('↓下载  ↑上传',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
            const SizedBox(height: 12),
            if (_rates != null)
              ..._rates!.map((n) => _buildRateCard(n))
            else
              ..._info!.networkInterfaces.map((n) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lan_rounded,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            n.model != null && n.model!.isNotEmpty
                                ? '${n.iface} · ${n.model}'
                                : n.iface,
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(n.speedLabel,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  )),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 磁盘状态光点颜色：异常红 / 未挂载灰 / 休眠黄 / 运行中绿
  Color _diskDotColor(ArrayDiskInfo d) {
    if (!d.isHealthy) return AppColors.red;
    if (!d.isMounted) return AppColors.textFaint;
    if (d.isSpinning == false) return AppColors.yellow;
    return AppColors.green;
  }

  Widget _buildDiskRow(ArrayDiskInfo d) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => DiskDetailScreen(
                  disk: d,
                  baseUrl: widget.api.baseUrl,
                )),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 9, color: _diskDotColor(d)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    d.fsSizeKb > 0
                        ? '${d.runStateLabel} · 已用 ${d.usedLabel}/${d.totalLabel}'
                        : d.runStateLabel,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (d.tempC != null) ...[
              Text('${d.tempC}°C',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  /// CPU 温度：优先用温度传感器（metrics.temperature），退回 info.cpu.packages
  double? get _cpuTempC {
    final temps = _temps;
    if (temps == null) return null;
    final packages = temps.where((t) => t.type == 'CPU_PACKAGE').toList();
    if (packages.isNotEmpty) {
      return packages
              .map((t) => t.valueCelsius)
              .reduce((a, b) => a + b) /
          packages.length;
    }
    final cores = temps.where((t) => t.type == 'CPU_CORE').toList();
    if (cores.isNotEmpty) {
      return cores.map((t) => t.valueCelsius).reduce((a, b) => a + b) /
          cores.length;
    }
    return null;
  }

  /// GPU 温度（lm-sensors 能读到才返回）
  double? get _gpuTempC {
    final temps = _temps;
    if (temps == null) return null;
    final gpu = temps.where((t) => t.type == 'GPU').toList();
    if (gpu.isEmpty) return null;
    return gpu.map((t) => t.valueCelsius).reduce((a, b) => a + b) / gpu.length;
  }

  String _cpuTempAndSpeedLabel() {
    final info = _info;
    final speed = info?.cpuSpeedGhz;
    final temp = _cpuTempC ?? info?.cpuAvgTemp;
    if (temp != null && speed != null) {
      return '${temp.toStringAsFixed(0)}°C · ${speed.toStringAsFixed(2)}GHz';
    }
    if (temp != null) return '${temp.toStringAsFixed(0)}°C';
    if (speed != null) return '${speed.toStringAsFixed(2)}GHz';
    return '温度/频率暂不支持';
  }

  Widget _buildRateCard(NetworkRateInfo n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: n.isUp ? AppColors.green : AppColors.textFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.name,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (n.utilizationPercent != null)
                  Text(
                    '链路利用率 ${n.utilizationPercent!.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward_rounded,
                      size: 13, color: AppColors.teal),
                  const SizedBox(width: 2),
                  Text(n.rxLabel,
                      style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward_rounded,
                      size: 13, color: AppColors.orange),
                  const SizedBox(width: 2),
                  Text(n.txLabel,
                      style: TextStyle(
                          color: AppColors.orange,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionError(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
