/// 系统信息快照：主机名 / 系统版本 / 运行时间 / CPU 静态信息 / 网卡静态信息。
/// 对应查询：info { os cpu devices }
class SystemInfoSnapshot {
  final String hostname;
  final String distro;
  final String uptime;

  final String cpuBrand;
  final String cpuManufacturer;
  final int cpuCores;
  final int cpuThreads;
  final double? cpuSpeedGhz;
  final List<double> cpuPackageTemps; // °C，每个物理封装一个

  final List<NetworkInterfaceInfo> networkInterfaces;

  SystemInfoSnapshot({
    required this.hostname,
    required this.distro,
    required this.uptime,
    required this.cpuBrand,
    required this.cpuManufacturer,
    required this.cpuCores,
    required this.cpuThreads,
    required this.cpuSpeedGhz,
    required this.cpuPackageTemps,
    required this.networkInterfaces,
  });

  factory SystemInfoSnapshot.fromJson(Map<String, dynamic> json) {
    final info = json['info'] ?? {};
    final os = info['os'] ?? {};
    final cpu = info['cpu'] ?? {};
    final packages = cpu['packages'] ?? {};
    final devices = info['devices'] ?? {};
    final netList = (devices['network'] as List?) ?? [];

    return SystemInfoSnapshot(
      hostname: os['hostname'] ?? '未知主机',
      distro: os['distro'] ?? '',
      uptime: os['uptime'] ?? '',
      cpuBrand: cpu['brand'] ?? '未知 CPU',
      cpuManufacturer: cpu['manufacturer'] ?? '',
      cpuCores: _toInt(cpu['cores']),
      cpuThreads: _toInt(cpu['threads']),
      cpuSpeedGhz: cpu['speed'] == null ? null : _toDouble(cpu['speed']),
      cpuPackageTemps: ((packages['temp'] as List?) ?? [])
          .map((t) => _toDouble(t))
          .where((t) => t > 0)
          .toList(),
      networkInterfaces: netList
          .map((n) => NetworkInterfaceInfo.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }

  /// CPU 封装平均温度（没有传感器数据时返回 null，界面上要显示"暂不支持"）
  double? get cpuAvgTemp {
    if (cpuPackageTemps.isEmpty) return null;
    return cpuPackageTemps.reduce((a, b) => a + b) / cpuPackageTemps.length;
  }

  /// 把 ISO 格式的开机时间转换成"12 天 4 小时"这种易读文案
  String get uptimeLabel {
    if (uptime.isEmpty) return '--';
    try {
      final dt = DateTime.parse(uptime);
      final diff = DateTime.now().difference(dt);
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      if (days > 0) return '$days 天 $hours 小时';
      if (diff.inHours > 0) {
        return '${diff.inHours} 小时 ${diff.inMinutes % 60} 分钟';
      }
      return '${diff.inMinutes} 分钟';
    } catch (_) {
      return uptime;
    }
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}

/// 实时指标快照：CPU / 内存占用。
/// 对应查询：metrics { cpu memory }
class MetricsSnapshot {
  final double cpuPercent;
  final double memPercent;
  final int memTotalBytes;
  final int memUsedBytes;

  MetricsSnapshot({
    required this.cpuPercent,
    required this.memPercent,
    required this.memTotalBytes,
    required this.memUsedBytes,
  });

  factory MetricsSnapshot.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] ?? {};
    final cpu = metrics['cpu'] ?? {};
    final mem = metrics['memory'] ?? {};

    final total = _toInt(mem['total']);
    final available = _toInt(mem['available']);
    final used = total - available;

    return MetricsSnapshot(
      cpuPercent: _toDouble(cpu['percentTotal']),
      // 注意：接口的 memory.used 字段在 Linux 上会把可回收的磁盘缓存/缓冲区
      // 也算进去，数值明显偏高，跟 Unraid 官方网页版看到的"已用"对不上。
      // 改用 total - available 计算真实已用量（available 是"刨除可回收缓存后
      // 实际可用的内存"），百分比也用同一个口径反推，保证环形图和下面的
      // "已用 X / 共 Y" 永远一致，且跟 Unraid 自己网页版的数字对得上。
      memPercent: total <= 0 ? 0 : ((used / total) * 100).clamp(0, 100),
      memTotalBytes: total,
      memUsedBytes: used,
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String get memUsedLabel => _formatBytes(memUsedBytes);
  String get memTotalLabel => _formatBytes(memTotalBytes);

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 GB';
    const gb = 1024 * 1024 * 1024;
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }
}

/// 阵列 + 磁盘快照：阵列状态 / 总容量 / 每块磁盘详情（含 SMART 合并）。
/// 对应查询：array { ... } + disks { ... }
class ArraySnapshot {
  final String arrayState;
  final ArrayCapacityInfo capacity;
  final List<ArrayDiskInfo> disks;

  ArraySnapshot({
    required this.arrayState,
    required this.capacity,
    required this.disks,
  });

  factory ArraySnapshot.fromJson(Map<String, dynamic> json) {
    final array = json['array'] ?? {};
    final disksJson = (array['disks'] as List?) ?? [];
    final cachesJson = (array['caches'] as List?) ?? [];

    // 顶层 disks 查询里有 SMART 健康状态 / 接口类型 / 序列号，
    // 按 device 路径（比如 /dev/sdb）跟阵列磁盘信息合并成一份完整数据。
    final topLevelDisks = (json['disks'] as List?) ?? [];
    final Map<String, Map<String, dynamic>> detailByDevice = {
      for (final d in topLevelDisks)
        if ((d as Map<String, dynamic>)['device'] != null) d['device']: d,
    };

    return ArraySnapshot(
      arrayState: array['state'] ?? 'UNKNOWN',
      capacity: ArrayCapacityInfo.fromJson(array['capacity'] ?? {}),
      disks: [...disksJson, ...cachesJson]
          .map((d) => ArrayDiskInfo.fromJson(
                d as Map<String, dynamic>,
                detailByDevice[d['device']],
              ))
          .toList(),
    );
  }
}

/// 阵列总容量（跨所有磁盘汇总），对应 array.capacity.kilobytes
class ArrayCapacityInfo {
  final int freeKb;
  final int usedKb;
  final int totalKb;

  ArrayCapacityInfo({
    required this.freeKb,
    required this.usedKb,
    required this.totalKb,
  });

  factory ArrayCapacityInfo.fromJson(Map<String, dynamic> json) {
    final kb = json['kilobytes'] ?? {};
    return ArrayCapacityInfo(
      freeKb: _toInt(kb['free']),
      usedKb: _toInt(kb['used']),
      totalKb: _toInt(kb['total']),
    );
  }

  double get usedPercent {
    if (totalKb <= 0) return 0;
    return (usedKb / totalKb * 100).clamp(0, 100);
  }

  String get usedLabel => ArrayDiskInfo._formatKb(usedKb);
  String get totalLabel => ArrayDiskInfo._formatKb(totalKb);

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}

class ArrayDiskInfo {
  final String name;
  final String device;
  final String status;
  final int? tempC;
  final String type;
  final int fsSizeKb; // 文件系统总容量（KB）
  final int fsUsedKb; // 文件系统已用容量（KB）
  final bool? isSpinning;

  // 以下字段来自顶层 disks 查询，只有匹配上时才有值
  final String? smartStatus; // OK / UNKNOWN
  final String? vendor;
  final String? interfaceType;
  final String? serialNum;

  ArrayDiskInfo({
    required this.name,
    required this.device,
    required this.status,
    required this.tempC,
    required this.type,
    required this.fsSizeKb,
    required this.fsUsedKb,
    required this.isSpinning,
    this.smartStatus,
    this.vendor,
    this.interfaceType,
    this.serialNum,
  });

  factory ArrayDiskInfo.fromJson(
    Map<String, dynamic> json, [
    Map<String, dynamic>? detail,
  ]) {
    return ArrayDiskInfo(
      name: json['name'] ?? json['device'] ?? '未知磁盘',
      device: json['device'] ?? '',
      status: json['status'] ?? 'DISK_NP',
      tempC: json['temp'] is int ? json['temp'] : null,
      type: json['type'] ?? 'DATA',
      fsSizeKb: _toInt(json['fsSize']),
      fsUsedKb: _toInt(json['fsUsed']),
      isSpinning: json['isSpinning'] is bool ? json['isSpinning'] : null,
      smartStatus: detail?['smartStatus'],
      vendor: detail?['vendor'],
      interfaceType: detail?['interfaceType'],
      serialNum: detail?['serialNum'],
    );
  }

  bool get isHealthy => status == 'DISK_OK';
  bool get isMounted => status == 'DISK_OK';

  /// 中文健康状态文案（基于阵列成员状态）
  String get healthLabel {
    switch (status) {
      case 'DISK_OK':
        return '健康';
      case 'DISK_NP':
        return '未安装';
      case 'DISK_NP_MISSING':
        return '缺失';
      case 'DISK_INVALID':
        return '无效';
      case 'DISK_WRONG':
        return '插错槽位';
      case 'DISK_DSBL':
      case 'DISK_NP_DSBL':
        return '已禁用';
      case 'DISK_DSBL_NEW':
        return '禁用(新盘)';
      case 'DISK_NEW':
        return '新磁盘';
      default:
        return status;
    }
  }

  /// SMART 健康状态文案（官方 API 目前只提供粗粒度的 OK / 未知两档，
  /// 没有详细的 SMART 属性表，比如重映射扇区数这类细项拿不到）
  String get smartLabel {
    switch (smartStatus) {
      case 'OK':
        return 'SMART 正常';
      case 'UNKNOWN':
        return 'SMART 未知';
      default:
        return '暂无 SMART 数据';
    }
  }

  /// 运行状态：运行中 / 休眠 / 未挂载
  String get runStateLabel {
    if (!isMounted) return '未挂载';
    if (isSpinning == null) return '未知';
    return isSpinning! ? '运行中' : '已休眠';
  }

  double get usedPercent {
    if (fsSizeKb <= 0) return 0;
    return (fsUsedKb / fsSizeKb * 100).clamp(0, 100);
  }

  String get usedLabel => _formatKb(fsUsedKb);
  String get totalLabel => _formatKb(fsSizeKb);

  static String _formatKb(int kb) {
    if (kb <= 0) return '--';
    final gb = kb / 1024 / 1024;
    if (gb >= 1024) return '${(gb / 1024).toStringAsFixed(1)} TB';
    return '${gb.toStringAsFixed(0)} GB';
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}

/// 网卡静态信息（协商带宽等），对应 info.devices.network
class NetworkInterfaceInfo {
  final String iface;
  final String? model;
  final String? speed;

  NetworkInterfaceInfo({
    required this.iface,
    required this.model,
    required this.speed,
  });

  factory NetworkInterfaceInfo.fromJson(Map<String, dynamic> json) {
    return NetworkInterfaceInfo(
      iface: json['iface'] ?? '未知网卡',
      model: json['model'],
      speed: json['speed'],
    );
  }

  /// 官方 API 这里只暴露网卡协商链路速度（比如 "1000"），不是实时占用率
  String get speedLabel => (speed != null && speed!.isNotEmpty) ? '$speed Mbps' : '未知带宽';
}

/// GPU 静态信息（PCI 设备），对应 info.devices.gpu
class GpuInfo {
  final String type;
  final String? vendorname;
  final String? productid;

  GpuInfo({required this.type, this.vendorname, this.productid});

  factory GpuInfo.fromJson(Map<String, dynamic> json) {
    return GpuInfo(
      type: json['type'] ?? '',
      vendorname: json['vendorname'],
      productid: json['productid'],
    );
  }

  String get label {
    if (vendorname != null && vendorname!.isNotEmpty) {
      return vendorname!;
    }
    return type.isNotEmpty ? type : '未知 GPU';
  }
}

/// 温度传感器（lm-sensors / smartctl / ipmi），对应 metrics.temperature.sensors
class TemperatureSensor {
  final String name;
  final String type; // CPU_PACKAGE / CPU_CORE / GPU / DISK / NVME / MOTHERBOARD ...
  final double valueCelsius;
  final String status; // NORMAL / WARNING / CRITICAL / UNKNOWN

  TemperatureSensor({
    required this.name,
    required this.type,
    required this.valueCelsius,
    required this.status,
  });

  factory TemperatureSensor.fromJson(Map<String, dynamic> json) {
    final current = json['current'] ?? {};
    return TemperatureSensor(
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      valueCelsius: _toCelsius(
        _toDouble(current['value']),
        (current['unit'] ?? 'CELSIUS').toString(),
      ),
      status: (current['status'] ?? 'UNKNOWN').toString(),
    );
  }

  static double _toCelsius(double value, String unit) {
    switch (unit) {
      case 'FAHRENHEIT':
        return (value - 32) * 5 / 9;
      case 'KELVIN':
        return value - 273.15;
      case 'RANKINE':
        return (value - 491.67) * 5 / 9;
      default:
        return value;
    }
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}
