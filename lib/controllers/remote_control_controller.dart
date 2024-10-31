import 'dart:async';
import 'dart:collection';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/websocket_service.dart';
import 'dart:convert';

class AccelerometerData {
  final double x;
  final double y;
  final double z;
  final int timestamp;

  AccelerometerData(this.x, this.y, this.z, this.timestamp);
}

class RemoteControlController extends GetxController {
  final WebSocketService _wsService = Get.find<WebSocketService>();

  // 상태 관리
  final isConnected = false.obs;
  final isPresentationMode = false.obs;
  final isLaserMode = false.obs;
  final mousePosition = Rx<Point>({'x': 0.0, 'y': 0.0});

  // 가속도 센서 관련 상수
  static const double accelerometerThreshold = 0.5;
  static const double sensitivityX = 15.0;
  static const double sensitivityY = 15.0;
  static const double smoothingFactor = 0.3;

  // 마우스 이동 관련 변수
  double _velocityX = 0.0;
  double _velocityY = 0.0;
  final Queue<AccelerometerData> _accelerometerQueue = Queue<AccelerometerData>();
  static const int _queueMaxLength = 5;
  Timer? _mouseMoveTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 활성화 관리
  Timer? _inactivityTimer;
  Timer? _keepAliveTimer;
  bool _isAccelerometerActive = false;

  @override
  void onInit() {
    super.onInit();
    WakelockPlus.enable();
    _startInactivityTimer();

    ever(isConnected, (bool connected) {
      if (connected) {
        print('Connected to server! Navigating to RemoteControlView');
        Get.toNamed('/remote_control');
        _startKeepAliveTimer();
        _startAccelerometer();
      } else {
        Get.offNamed('/qr_scan');
        _keepAliveTimer?.cancel();
        _stopAccelerometer();
      }
    });
  }

  void _startAccelerometer() {
    if (_isAccelerometerActive) return;

    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (!isConnected.value || !_isAccelerometerActive) return;

      // 중력 가속도 보정 (기기 방향에 따라 조정 필요할 수 있음)
      double x = event.x;
      double y = event.y;

      // 노이즈 필터링
      if (x.abs() < accelerometerThreshold && y.abs() < accelerometerThreshold) return;

      _updateAccelerometerQueue(event);
      final avgAcceleration = _calculateAverageAcceleration();

      // 속도 계산 및 부드러운 이동
      _velocityX += (avgAcceleration.x * sensitivityX - _velocityX) * smoothingFactor;
      _velocityY += (avgAcceleration.y * sensitivityY - _velocityY) * smoothingFactor;

      _sendMouseMoveCommand();
    });

    _isAccelerometerActive = true;
  }

  void _stopAccelerometer() {
    _accelerometerSubscription?.cancel();
    _isAccelerometerActive = false;
    _velocityX = 0;
    _velocityY = 0;
    _accelerometerQueue.clear();
  }

  void _updateAccelerometerQueue(AccelerometerEvent event) {
    _accelerometerQueue.add(AccelerometerData(
      event.x,
      event.y,
      event.z,
      DateTime.now().millisecondsSinceEpoch,
    ));
    if (_accelerometerQueue.length > _queueMaxLength) {
      _accelerometerQueue.removeFirst();
    }
  }

  AccelerometerEvent _calculateAverageAcceleration() {
    if (_accelerometerQueue.isEmpty) {
      return AccelerometerEvent(0, 0, 0, DateTime.now());
    }

    double sumX = 0, sumY = 0, sumZ = 0;
    int latestTimestamp = _accelerometerQueue.last.timestamp;

    for (var data in _accelerometerQueue) {
      sumX += data.x;
      sumY += data.y;
      sumZ += data.z;
    }

    return AccelerometerEvent(sumX / _accelerometerQueue.length, sumY / _accelerometerQueue.length, sumZ / _accelerometerQueue.length,
        DateTime.fromMillisecondsSinceEpoch(latestTimestamp));
  }

  void _sendMouseMoveCommand() {
    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(const Duration(milliseconds: 16), () {
      if (!isConnected.value) return;

      _wsService.sendCommand({
        'type': 'mouse_move_relative',
        'dx': -_velocityX,
        'dy': _velocityY,
        'is_laser': isLaserMode.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 10), () {
      disconnect();
    });
  }

  void _resetInactivityTimer() {
    _startInactivityTimer();
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected.value) {
        _wsService.sendCommand({'type': 'keepalive'});
      }
    });
  }

  void _handleUserInput() {
    _resetInactivityTimer();
  }

  Future<void> connectWithCode(String input) async {
    try {
      print('Attempting to connect with input: $input');
      Map<String, dynamic> connectionData;

      if (input.startsWith('{')) {
        connectionData = json.decode(input);
        connectionData['wsUrl'] = 'ws://${connectionData['ip']}:${connectionData['port']}';
      } else {
        connectionData = {'code': input, 'wsUrl': 'ws://192.168.0.x:8080'};
      }

      print('Connecting with data: $connectionData');

      final Uri wsUri = Uri.parse(connectionData['wsUrl']);
      await _wsService.connectToServer(wsUri.host, wsUri.port, connectionData['code'].toString());

      if (_wsService.isConnected.value) {
        isConnected.value = true;
        print('Successfully connected to server');
        Get.offNamed('/remote_control');
      } else {
        throw Exception('WebSocket connection failed');
      }
    } catch (e) {
      print('Connection error: $e');
      isConnected.value = false;
      Get.snackbar(
        '연결 오류',
        '서버 연결에 실패했습니다: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
      );
      rethrow;
    }
  }

  void sendClick(String type) {
    if (!isConnected.value) return;
    _handleUserInput();
    _wsService.sendCommand({
      'type': 'mouse_click',
      'click_type': type,
    });
  }

  void sendKeyCommand(String key) {
    if (!isConnected.value) return;
    _handleUserInput();
    print('Sending key command: $key');
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': key,
    });
  }

  void nextSlide() {
    if (!isConnected.value) return;
    print('Sending next slide command');
    sendKeyCommand('right');
  }

  void previousSlide() {
    if (!isConnected.value) return;
    print('Sending previous slide command');
    sendKeyCommand('left');
  }

  void toggleBlackScreen() {
    if (!isConnected.value) return;
    print('Sending black screen command');
    sendKeyCommand('b');
  }

  void toggleWhiteScreen() {
    if (!isConnected.value) return;
    print('Sending white screen command');
    sendKeyCommand('w');
  }

  void togglePresentationMode() {
    if (!isConnected.value) return;
    isPresentationMode.toggle();
    print('Toggling presentation mode: ${isPresentationMode.value}');
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': isPresentationMode.value ? 'f5' : 'esc',
    });
  }

  void toggleLaserMode() {
    isLaserMode.toggle();
    if (isLaserMode.value) {
      _stopAccelerometer();
    } else {
      _startAccelerometer();
    }
  }

  void disconnect() {
    if (!isConnected.value) return;
    _wsService.sendCommand({
      'type': 'disconnect',
    });
    _wsService.disconnect();
    isConnected.value = false;
    isPresentationMode.value = false;
    isLaserMode.value = false;
    _stopAccelerometer();
  }

  void updateMousePosition(double x, double y) {
    mousePosition.value = {'x': x, 'y': y};
    if (isConnected.value) {
      _wsService.sendCommand({
        'type': 'mouse_move_absolute',
        'x': x,
        'y': y,
        'is_laser': isLaserMode.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void adjustVolume(double value) {
    if (!isConnected.value) return;
    _handleUserInput();
    _wsService.sendCommand({
      'type': 'volume_adjust',
      'value': value,
    });
  }

  @override
  void onClose() {
    WakelockPlus.disable();
    _inactivityTimer?.cancel();
    _keepAliveTimer?.cancel();
    _mouseMoveTimer?.cancel();
    _stopAccelerometer();
    disconnect();
    super.onClose();
  }
}

typedef Point = Map<String, double>;
