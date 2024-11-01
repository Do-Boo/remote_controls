import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/udp_service.dart';
import 'dart:convert';

class RemoteControlController extends GetxController {
  final UDPService _udpService = Get.find<UDPService>();

  // 상태 관리
  final isConnected = false.obs;
  final isPresentationMode = false.obs;
  final isLaserMode = false.obs;
  final mousePosition = Rx<Point>({'x': 0.0, 'y': 0.0});

  // 가속도계 관련 상수
  static const double accelerometerThreshold = 0.02; // 더 작은 임계값
  static const double _baseAcceleration = 0.8; // 기본 감도
  static const double _minMovement = 0.1; // 최소 움직임 임계값
  static const double _normalMovement = 0.5; // 일반 움직임 임계값
  static const double _maxAcceleration = 1.5; // 최대 가속도
  static const double _smoothingFactor = 0.4; // 부드러움 계수

  // 이동 평균을 위한 큐
  final Queue<AccelerometerEvent> _accelerometerQueue = Queue<AccelerometerEvent>();
  static const int _queueMaxLength = 5;

  // 마우스 이동 관련 변수
  double _accumulatedDx = 0.0;
  double _accumulatedDy = 0.0;
  Timer? _mouseMoveTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 활성화 관리
  Timer? _inactivityTimer;
  bool _isAccelerometerActive = false;

  @override
  void onInit() {
    super.onInit();
    WakelockPlus.enable();
    _startInactivityTimer();

    // UDP 서비스 연결 상태 감시
    ever(_udpService.isConnected, (bool connected) {
      isConnected.value = connected;
      if (connected) {
        print('Connected to server! Navigating to RemoteControlView');
        Get.toNamed('/remote_control');
        _startAccelerometer();
      } else {
        print('Disconnected from server');
        Get.offNamed('/qr_scan');
        _stopAccelerometer();
      }
    });
  }

  Future<void> connectWithCode(String input) async {
    try {
      print('Attempting to connect with input: $input');
      Map<String, dynamic> connectionData;

      if (input.startsWith('{')) {
        connectionData = json.decode(input);
        print('QRScanView: Parsed JSON data: $connectionData');
      } else {
        print('Invalid connection data format');
        throw Exception('잘못된 연결 데이터');
      }

      print('Connecting with data: $connectionData');

      await _udpService.connectToServer(
        connectionData['ip'],
        connectionData['port'],
        connectionData['code'].toString(),
      );
    } catch (e) {
      print('Connection error: $e');
      Get.snackbar(
        '연결 오류',
        '서버 연결에 실패했습니다: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
      );
      rethrow;
    }
  }

  void _startAccelerometer() {
    if (_isAccelerometerActive) return;

    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (!isConnected.value || !_isAccelerometerActive) return;

      // 가속도 데이터 처리
      final acceleration = _processAccelerometerData(event);
      if (acceleration != null) {
        _updateMouseMovement(acceleration);
      }
    });

    _isAccelerometerActive = true;
  }

  AccelerationData? _processAccelerometerData(AccelerometerEvent event) {
    // 노이즈 필터링
    if (event.x.abs() < accelerometerThreshold && event.y.abs() < accelerometerThreshold) {
      return null;
    }

    // 이동 평균 계산을 위해 큐에 추가
    _accelerometerQueue.add(event);
    if (_accelerometerQueue.length > _queueMaxLength) {
      _accelerometerQueue.removeFirst();
    }

    // 평균 가속도 계산
    double avgX = 0.0, avgY = 0.0;
    for (var e in _accelerometerQueue) {
      avgX += e.x;
      avgY += e.y;
    }
    avgX /= _accelerometerQueue.length;
    avgY /= _accelerometerQueue.length;

    // 움직임의 크기 계산
    final movement = sqrt(avgX * avgX + avgY * avgY);

    // 감도 계산
    double sensitivity = _baseAcceleration;
    if (movement < _minMovement) {
      sensitivity *= 0.3;
    } else if (movement < _normalMovement) {
      sensitivity *= 1.0;
    } else {
      final acceleration = min(_maxAcceleration, 1.0 + (movement - _normalMovement) * 0.3);
      sensitivity *= acceleration;
    }

    return AccelerationData(
      dx: avgX * sensitivity,
      dy: avgY * sensitivity,
    );
  }

  void _updateMouseMovement(AccelerationData acceleration) {
    // 이동 거리 누적
    _accumulatedDx += acceleration.dx;
    _accumulatedDy += acceleration.dy;

    // 부드러운 이동을 위해 타이머 사용
    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(const Duration(milliseconds: 16), () {
      if (!isConnected.value) return;

      // 실제 이동할 거리 계산
      final dx = _accumulatedDx * _smoothingFactor;
      final dy = _accumulatedDy * _smoothingFactor;

      // 남은 거리 저장
      _accumulatedDx -= dx;
      _accumulatedDy -= dy;

      // 이동 명령 전송
      _sendMouseMoveCommand(dx, dy);
    });
  }

  void _sendMouseMoveCommand(double dx, double dy) {
    _udpService.sendCommand({
      'type': 'mouse_move_relative',
      'dx': -dx, // x축 반전
      'dy': dy,
      'is_laser': isLaserMode.value,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _stopAccelerometer() {
    _accelerometerSubscription?.cancel();
    _isAccelerometerActive = false;
    _accelerometerQueue.clear();
    _accumulatedDx = 0;
    _accumulatedDy = 0;
    _mouseMoveTimer?.cancel();
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

  void _handleUserInput() {
    _resetInactivityTimer();
  }

  // 마우스 제어
  void sendClick(String type) {
    if (!isConnected.value) return;
    _handleUserInput();

    _udpService.sendCommand({
      'type': 'mouse_click',
      'click_type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // 키보드 제어
  void sendKeyCommand(String key) {
    if (!isConnected.value) return;
    _handleUserInput();

    print('Sending key command: $key');
    _udpService.sendCommand({
      'type': 'keyboard',
      'key': key,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // 프레젠테이션 제어
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
    _udpService.sendCommand({
      'type': 'keyboard',
      'key': isPresentationMode.value ? 'f5' : 'esc',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void toggleLaserMode() {
    isLaserMode.toggle();
    print('Toggling laser mode: ${isLaserMode.value}');
    if (isLaserMode.value) {
      _stopAccelerometer();
    } else {
      _startAccelerometer();
    }
  }

  void disconnect() {
    if (!isConnected.value) return;
    print('Disconnecting from server');
    _udpService.sendCommand({
      'type': 'disconnect',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _udpService.disconnect();
    isConnected.value = false;
    isPresentationMode.value = false;
    isLaserMode.value = false;
    _stopAccelerometer();
  }

  @override
  void onClose() {
    print('Closing RemoteControlController');
    WakelockPlus.disable();
    _inactivityTimer?.cancel();
    _mouseMoveTimer?.cancel();
    _stopAccelerometer();
    disconnect();
    super.onClose();
  }
}

// 보조 클래스
class AccelerationData {
  final double dx;
  final double dy;

  AccelerationData({required this.dx, required this.dy});
}

typedef Point = Map<String, double>;
