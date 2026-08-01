enum VmState {
  running,
  idle,
  paused,
  shutdown,
  shutoff,
  crashed,
  pmsuspended,
  nostate,
}

class VmDomainInfo {
  final String id;
  final String name;
  final VmState state;

  VmDomainInfo({required this.id, required this.name, required this.state});

  factory VmDomainInfo.fromJson(Map<String, dynamic> json) {
    return VmDomainInfo(
      id: json['id'] ?? '',
      name: (json['name'] ?? '未命名虚拟机').toString(),
      state: _parseState(json['state']),
    );
  }

  static VmState _parseState(dynamic raw) {
    switch (raw) {
      case 'RUNNING':
        return VmState.running;
      case 'IDLE':
        return VmState.idle;
      case 'PAUSED':
        return VmState.paused;
      case 'SHUTDOWN':
        return VmState.shutdown;
      case 'SHUTOFF':
        return VmState.shutoff;
      case 'CRASHED':
        return VmState.crashed;
      case 'PMSUSPENDED':
        return VmState.pmsuspended;
      default:
        return VmState.nostate;
    }
  }
}
