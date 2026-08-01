/// 单块网卡的实时流量指标，对应查询：metrics { network { ... } }。
///
/// 字段名已按官方 API 源码核对（api/src/.../metrics/network/network.model.ts）：
/// - rxSec / txSec：接收 / 发送吞吐，单位 字节/秒（实时速率）
/// - utilizationPercent：估算的链路利用率（0~100，可空）
/// - operstate：up / down 等
class NetworkRateInfo {
  final String name; // 接口名，如 eth0
  final String? operstate;
  final double rxSec; // 字节/秒
  final double txSec; // 字节/秒
  final double? utilizationPercent;
  final DateTime? lastUpdated;

  NetworkRateInfo({
    required this.name,
    required this.operstate,
    required this.rxSec,
    required this.txSec,
    required this.utilizationPercent,
    required this.lastUpdated,
  });

  factory NetworkRateInfo.fromJson(Map<String, dynamic> json) {
    return NetworkRateInfo(
      name: json['name'] ?? '未知网卡',
      operstate: json['operstate']?.toString(),
      rxSec: _toDouble(json['rxSec']),
      txSec: _toDouble(json['txSec']),
      utilizationPercent: json['utilizationPercent'] == null
          ? null
          : _toDouble(json['utilizationPercent']),
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.tryParse(json['lastUpdated'].toString()),
    );
  }

  bool get isUp => operstate?.toLowerCase() == 'up';

  /// 下载速率文案，如 "1.2 MB/s"
  String get rxLabel => _formatRate(rxSec);

  /// 上传速率文案，如 "340 KB/s"
  String get txLabel => _formatRate(txSec);

  static String _formatRate(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    double v = bytesPerSec;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}
