import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:get/get.dart';

class WebSocketService extends GetxService {
  WebSocketChannel? _channel;
  final isConnected = false.obs;

  Future<void> connectToServer(String ip, int port, String code) async {
    try {
      final wsUrl = 'ws://$ip:$port';
      print('Connecting to WebSocket server at: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 연결 상태 모니터링
      _channel!.stream.listen(
        (message) {
          print('Received from server: $message');
          final data = json.decode(message);
          if (data['type'] == 'connection_status') {
            isConnected.value = data['status'] == 'connected';
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          isConnected.value = false;
          _channel = null;
        },
        onDone: () {
          print('WebSocket connection closed');
          isConnected.value = false;
          _channel = null;
        },
      );
    } catch (e) {
      print('Connection error: $e');
      isConnected.value = false;
      rethrow;
    }
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_channel != null) {
      print('Sending command: $command');
      _channel!.sink.add(json.encode(command));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    isConnected.value = false;
  }
}
