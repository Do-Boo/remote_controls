import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:get/get.dart';

class WebSocketService extends GetxService {
  WebSocketChannel? _channel;
  final isConnected = false.obs;

  Future<void> connectToServer(String ip, int port, String code) async {
    try {
      // 기존 연결이 있다면 해제
      disconnect();

      final wsUrl = 'ws://$ip:$port';
      print('Connecting to WebSocket server at: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 연결 성공 여부를 확인하기 위한 Completer 추가
      final connectionCompleter = Completer<bool>();

      // 연결 상태 모니터링
      _channel!.stream.listen(
        (message) {
          print('Received from server: $message');
          try {
            final data = json.decode(message);
            if (data['type'] == 'auth_response') {
              isConnected.value = data['status'] == 'success';
              print('Authentication status: ${isConnected.value}');
              if (!connectionCompleter.isCompleted) {
                connectionCompleter.complete(isConnected.value);
              }

              // 연결 실패 시 에러 메시지 표시
              if (!isConnected.value) {
                Get.snackbar(
                  '연결 실패',
                  data['message'] ?? '알 수 없는 오류가 발생했습니다.',
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            }
          } catch (e) {
            print('Error parsing message: $e');
            if (!connectionCompleter.isCompleted) {
              connectionCompleter.complete(false);
            }
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          isConnected.value = false;
          _channel = null;
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
        },
        onDone: () {
          print('WebSocket connection closed');
          isConnected.value = false;
          _channel = null;
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
        },
      );

      // 초기 인증 메시지 전송
      _channel!.sink.add(json.encode({'type': 'auth', 'code': code, 'client_type': 'control'}));

      // 연결 타임아웃 설정 (3초)
      final result = await connectionCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print('Connection timeout');
          return false;
        },
      );

      if (!result) {
        throw Exception(isConnected.value ? '연결이 거부되었습니다' : '연결 시간 초과');
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
