class ConnectionInfo {
  final String code;
  final String serverIp;
  final int serverPort;
  final DateTime connectedAt;

  ConnectionInfo({
    required this.code,
    required this.serverIp,
    required this.serverPort,
    required this.connectedAt,
  });

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    return ConnectionInfo(
      code: json['code'],
      serverIp: json['server_ip'],
      serverPort: json['server_port'],
      connectedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'server_ip': serverIp,
      'server_port': serverPort,
      'connected_at': connectedAt.toIso8601String(),
    };
  }
}
