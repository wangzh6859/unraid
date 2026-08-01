enum ContainerState { running, paused, exited, unknown }

class DockerContainerInfo {
  final String id;
  final String name;
  final String image;
  final ContainerState state;
  final String status;
  final bool autoStart;
  final String? iconUrl;

  DockerContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.autoStart,
    required this.iconUrl,
  });

  factory DockerContainerInfo.fromJson(Map<String, dynamic> json) {
    final names = (json['names'] as List?) ?? [];
    String rawName =
        names.isNotEmpty ? names.first.toString() : (json['id'] ?? '未知容器');
    if (rawName.startsWith('/')) rawName = rawName.substring(1);

    return DockerContainerInfo(
      id: json['id'] ?? '',
      name: rawName,
      image: json['image'] ?? '',
      state: _parseState(json['state']),
      status: json['status'] ?? '',
      autoStart: json['autoStart'] == true,
      iconUrl: json['iconUrl'],
    );
  }

  static ContainerState _parseState(dynamic raw) {
    switch (raw) {
      case 'RUNNING':
        return ContainerState.running;
      case 'PAUSED':
        return ContainerState.paused;
      case 'EXITED':
        return ContainerState.exited;
      default:
        return ContainerState.unknown;
    }
  }
}
