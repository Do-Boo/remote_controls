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

      // 초기 연결 메시지에 client_type 추가
      _channel!.sink.add(json.encode({
        'type': 'auth',
        'code': code,
        'client_type': 'control' // 제어 클라이언트임을 명시
      }));

      // 연결 상태 모니터링
      _channel!.stream.listen(
        (message) {
          print('Received from server: $message');
          try {
            final data = json.decode(message);
            if (data['type'] == 'auth_response') {
              isConnected.value = data['status'] == 'success';
              print('Authentication status: ${isConnected.value}');
            }
          } catch (e) {
            print('Error parsing message: $e');
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

      // 연결 타임아웃 설정
      await Future.delayed(const Duration(seconds: 5));
      if (!isConnected.value) {
        throw Exception('Connection timeout');
      }
    } catch (e) {
      print('Connection error: $e');
      isConnected.value = false;
      _channel?.sink.close();
      _channel = null;
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
