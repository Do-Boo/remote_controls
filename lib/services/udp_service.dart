import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum ConnectionState { disconnected, connecting, authenticating, connected }

class UDPService extends GetxController {
  // 소켓 및 네트워크 관련
  RawDatagramSocket? _socket;
  InternetAddress? _serverAddress;
  int? _serverPort;

  // 타이머 관리
  Timer? _connectionTimer;
  Timer? _authTimer;
  Timer? _keepAliveTimer;

  // 연결 상태 관리
  String? _lastAttemptedCode;
  int _retryCount = 0;
  bool _isConnecting = false;

  // 상수
  static const int maxRetries = 3;
  static const int authTimeoutSeconds = 3;
  static const int connectionTimeoutSeconds = 10;
  static const int keepAliveIntervalSeconds = 5;

  // 옵저버블 상태
  final isConnected = false.obs;
  final connectionState = ConnectionState.disconnected.obs;

  /// 서버 연결 시도
  Future<void> connectToServer(String host, int port, String code) async {
    if (_isConnecting) {
      print('Connection attempt already in progress');
      return;
    }

    try {
      _isConnecting = true;
      print('Attempting to connect to $host:$port with code: $code');
      await _initializeConnection(host, port, code);
    } catch (e) {
      print('Connection failed: $e');
      await _handleConnectionError(e);
    } finally {
      _isConnecting = false;
    }
  }

  /// 연결 초기화
  Future<void> _initializeConnection(String host, int port, String code) async {
    await _cleanup(); // 이전 연결 정리

    connectionState.value = ConnectionState.connecting;
    print('Initializing UDP connection to $host:$port');

    try {
      _serverAddress = await InternetAddress.lookup(host).then((value) => value.first);
      _serverPort = port;
      print('Server address resolved: ${_serverAddress?.address}');

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      print('UDP socket bound to port ${_socket?.port}');

      _setupSocketListener();
      await _startAuthentication(code);
    } catch (e) {
      print('Connection initialization failed: $e');
      throw Exception('연결 초기화 실패: $e');
    }
  }

  /// 소켓 리스너 설정
  void _setupSocketListener() {
    _socket?.listen(
      (RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            print('Received data from ${datagram.address.address}:${datagram.port}');
            _handleMessage(datagram.data);
          }
        }
      },
      onError: (error) {
        print('Socket error: $error');
        _handleConnectionError(error);
      },
      onDone: () {
        print('Socket connection closed');
        _cleanup();
      },
    );
  }

  /// 메시지 처리
  void _handleMessage(List<int> data) {
    try {
      final message = utf8.decode(data);
      print('Decoded message: $message');

      final decoded = json.decode(message);
      final messageType = decoded['type'] as String;

      switch (messageType) {
        case 'auth_response':
          _handleAuthResponse(decoded);
          break;
        case 'error':
          _handleServerError(decoded['message'] ?? '알 수 없는 오류');
          break;
        case 'keepalive_response':
          print('Keepalive response received');
          break;
        default:
          print('Unknown message type: $messageType');
      }
    } catch (e) {
      print('Message handling error: $e');
    }
  }

  /// 인증 응답 처리
  void _handleAuthResponse(Map<String, dynamic> response) {
    _authTimer?.cancel();

    if (response['status'] == 'success') {
      print('Authentication successful');
      isConnected.value = true;
      connectionState.value = ConnectionState.connected;
      _connectionTimer?.cancel();
      _startKeepAlive();
    } else {
      print('Authentication failed: ${response['message']}');
      _handleServerError(response['message'] ?? '인증 실패');
    }
  }

  /// 서버 에러 처리
  Future<void> _handleServerError(String message) async {
    print('Server error: $message');

    if (message.contains('Invalid connection code')) {
      await _cleanup();

      final shouldRetry = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('인증 실패'),
          content: const Text('잘못된 연결 코드입니다.\n다시 시도하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () {
                Get.back(result: false);
                Get.offNamed('/qr_scan');
              },
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('재시도'),
            ),
          ],
        ),
        barrierDismissible: false,
      );

      if (shouldRetry == true) {
        // 재시도를 위한 상태 초기화
        _retryCount = 0;
        _isConnecting = false;
        connectionState.value = ConnectionState.disconnected;

        if (_lastAttemptedCode != null && _serverAddress != null && _serverPort != null) {
          final lastCode = _lastAttemptedCode!;
          final lastAddress = _serverAddress!.address;
          final lastPort = _serverPort!;

          _lastAttemptedCode = null;
          await connectToServer(lastAddress, lastPort, lastCode);
        }
      }
    } else {
      await _cleanup();
      await _showErrorDialog('서버 오류', '서버에서 오류가 발생했습니다: $message');
    }
  }

  /// 연결 오류 처리
  Future<void> _handleConnectionError(dynamic error) async {
    print('Connection error: $error');
    await _cleanup();
    await _showErrorDialog('연결 오류', '서버와 연결할 수 없습니다: $error');
  }

  /// 인증 시작
  Future<void> _startAuthentication(String code) async {
    _lastAttemptedCode = code;
    connectionState.value = ConnectionState.authenticating;
    _retryCount = 0;
    await _tryAuthentication();
  }

  /// 인증 시도
  Future<void> _tryAuthentication() async {
    if (_retryCount >= maxRetries) {
      await _showErrorDialog(
        '인증 실패',
        '여러 번의 시도에도 연결이 되지 않았습니다.\n잠시 후 다시 시도해주세요.',
      );
      return;
    }

    print('Attempting authentication (try ${_retryCount + 1}/$maxRetries)');

    _sendAuthCommand();
    _setupAuthenticationTimers();
  }

  /// 인증 명령 전송
  void _sendAuthCommand() {
    if (_lastAttemptedCode == null) return;

    sendCommand({
      'type': 'auth',
      'code': _lastAttemptedCode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'client_info': {
        'version': '1.0.0',
        'platform': Platform.operatingSystem,
        'retry_count': _retryCount,
      }
    });
  }

  /// 인증 타이머 설정
  void _setupAuthenticationTimers() {
    // 인증 재시도 타이머
    _authTimer?.cancel();
    _authTimer = Timer(const Duration(seconds: authTimeoutSeconds), () {
      if (!isConnected.value && connectionState.value == ConnectionState.authenticating) {
        _retryCount++;
        _tryAuthentication();
      }
    });

    // 전체 연결 타임아웃 타이머
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: connectionTimeoutSeconds), () {
      if (!isConnected.value) {
        _showErrorDialog('연결 시간 초과', '서버 응답이 없습니다.');
        _cleanup();
      }
    });
  }

  /// 킵얼라이브 시작
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: keepAliveIntervalSeconds),
      (_) {
        if (isConnected.value) {
          sendCommand({
            'type': 'keepalive',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      },
    );
  }

  /// 명령 전송
  void sendCommand(Map<String, dynamic> command) {
    if (_socket == null || _serverAddress == null || _serverPort == null) {
      print('Cannot send command: Socket not initialized');
      return;
    }

    try {
      final data = utf8.encode(json.encode(command));
      final sent = _socket!.send(data, _serverAddress!, _serverPort!);
      print('Sent UDP packet (${data.length} bytes): $sent');

      if (sent <= 0) {
        print('Failed to send UDP packet');
        if (command['type'] != 'disconnect') {
          _handleConnectionError('패킷 전송 실패');
        }
      }
    } catch (e) {
      print('Error sending command: $e');
      if (command['type'] != 'disconnect') {
        _handleConnectionError(e);
      }
    }
  }

  /// 에러 다이얼로그 표시
  Future<void> _showErrorDialog(String title, String message) async {
    await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              Get.offNamed('/qr_scan');
            },
            child: const Text('확인'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// 연결 정리
  Future<void> _cleanup() async {
    print('Cleaning up UDP service...');
    _authTimer?.cancel();
    _connectionTimer?.cancel();
    _keepAliveTimer?.cancel();

    if (_socket != null) {
      try {
        if (isConnected.value && _serverAddress != null && _serverPort != null) {
          final data = utf8.encode(json.encode({
            'type': 'disconnect',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          _socket!.send(data, _serverAddress!, _serverPort!);
        }
      } catch (e) {
        print('Error sending disconnect message: $e');
      } finally {
        _socket!.close();
        _socket = null;
      }
    }

    _serverAddress = null;
    _serverPort = null;
    isConnected.value = false;
    connectionState.value = ConnectionState.disconnected;
    print('Cleanup completed');
  }

  /// 연결 해제
  void disconnect() {
    print('Disconnecting UDP service');
    _cleanup();
  }

  @override
  void onClose() {
    disconnect();
    super.onClose();
  }
}
