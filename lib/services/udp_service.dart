import 'dart:io';
import 'dart:convert';
import 'package:get/get.dart';
import '../models/connection_info.dart';

class UdpService extends GetxService {
  RawDatagramSocket? _socket;
  final connectionInfo = Rx<ConnectionInfo?>(null);

  // 연결 상태
  final isConnected = false.obs;

  // 서버 정보
  InternetAddress? _serverAddress;
  int? _serverPort;

  @override
  void onInit() {
    super.onInit();
    initSocket().catchError((error) {
      print('UDP Socket initialization error: $error');
      // 오류가 발생해도 앱이 종료되지 않도록 처리
    });
  }

  // UDP 소켓 초기화
  Future<void> initSocket() async {
    try {
      if (_socket != null) return; // 이미 초기화된 경우 스킵

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket?.broadcastEnabled = true;
      _listenToSocket();
    } catch (e) {
      print('Socket initialization error: $e');
      // 오류를 throw하지 않고 처리
    }
  }

  // 소켓 리스너 설정
  void _listenToSocket() {
    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket?.receive();
        if (datagram != null) {
          _handleDatagram(datagram);
        }
      }
    });
  }

  // 데이터그램 처리
  void _handleDatagram(Datagram datagram) {
    try {
      final data = json.decode(utf8.decode(datagram.data));

      if (data['type'] == 'discovery_response') {
        _handleDiscoveryResponse(data, datagram.address, datagram.port);
      }
    } catch (e) {
      print('Datagram handling error: $e');
    }
  }

  // Discovery 응답 처리
  void _handleDiscoveryResponse(Map<String, dynamic> data, InternetAddress address, int port) {
    _serverAddress = address;
    _serverPort = data['control_port'];

    connectionInfo.value = ConnectionInfo(
      code: data['code'],
      serverIp: address.address,
      serverPort: data['control_port'],
      connectedAt: DateTime.now(),
    );

    isConnected.value = true;
  }

  // 연결 코드로 서버 검색
  Future<void> discoveryWithCode(String code) async {
    if (_socket == null) await initSocket();

    final discovery = {
      'type': 'discovery',
      'code': code,
    };

    try {
      final data = utf8.encode(json.encode(discovery));
      _socket?.send(data, InternetAddress('255.255.255.255'), 35001);
    } catch (e) {
      print('Discovery error: $e');
      rethrow;
    }
  }

  // 명령 전송
  void sendCommand(Map<String, dynamic> command) {
    if (!isConnected.value || _socket == null || _serverAddress == null) return;

    try {
      final data = utf8.encode(json.encode(command));
      _socket?.send(data, _serverAddress!, _serverPort!);
    } catch (e) {
      print('Send command error: $e');
    }
  }

  @override
  void onClose() {
    _socket?.close();
    super.onClose();
  }
}
