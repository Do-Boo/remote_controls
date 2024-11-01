import 'dart:async';
import 'dart:math' show acos, atan2, pi, sqrt;
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/udp_service.dart';
import 'dart:convert';

/// 센서 데이터를 처리하기 위한 클래스
class SensorData {
  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  SensorData(this.x, this.y, this.z) : timestamp = DateTime.now();

  /// 벡터의 크기 계산
  double get magnitude => sqrt(x * x + y * y + z * z);

  /// 다른 센서 데이터와의 각도 차이 계산
  double angleTo(SensorData other) {
    final dot = x * other.x + y * other.y + z * other.z;
    final mags = magnitude * other.magnitude;
    return mags != 0 ? acos(dot / mags) : 0;
  }
}

/// 포인터 위치 및 방향 정보를 관리하는 클래스
class PointerState {
  double x;
  double y;
  double pitch;
  double yaw;
  double roll;

  PointerState({
    this.x = 0.5,
    this.y = 0.5,
    this.pitch = 0,
    this.yaw = 0,
    this.roll = 0,
  });

  void reset() {
    x = 0.5;
    y = 0.5;
    pitch = 0;
    yaw = 0;
    roll = 0;
  }

  Map<String, double> toJson() => {
        'x': x,
        'y': y,
        'pitch': pitch,
        'yaw': yaw,
        'roll': roll,
      };
}

class RemoteControlController extends GetxController {
  static const int UPDATE_INTERVAL_MS = 16; // ~60Hz
  static const int CALIBRATION_SAMPLES = 50;
  static const double POINTER_SENSITIVITY = 1.2;
  static const double SMOOTHING_FACTOR = 0.85;
  static const double MAX_ANGLE_DEG = 45.0;

  final UDPService _udpService = Get.find<UDPService>();

  // 상태 관리
  final isConnected = false.obs;
  final isPresentationMode = false.obs;
  final isLaserMode = false.obs;
  final isCalibrating = false.obs;
  final calibrationProgress = 0.obs;

  // 센서 구독
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  // 타이머
  Timer? _updateTimer;
  Timer? _inactivityTimer;

  // 센서 데이터 처리
  final List<SensorData> _calibrationData = [];
  final _pointerState = PointerState();
  SensorData? _baseOrientation;
  DateTime _lastUpdateTime = DateTime.now();
  bool _isPointerActive = false;

  // 칼만 필터 상태
  double _kalmanAngleX = 0.0;
  double _kalmanAngleY = 0.0;
  double _kalmanUncertaintyX = 2 * 2;
  double _kalmanUncertaintyY = 2 * 2;
  static const double _kalmanQ = 0.001;
  static const double _kalmanR = 0.03;

  @override
  void onInit() {
    super.onInit();
    WakelockPlus.enable();
    _startInactivityTimer();

    ever(_udpService.isConnected, _handleConnectionChange);
    ever(isLaserMode, _handleLaserModeChange);
  }

  void _handleConnectionChange(bool connected) {
    isConnected.value = connected;
    if (connected) {
      print('Connected to server! Navigating to RemoteControlView');
      Get.toNamed('/remote_control');
    } else {
      print('Disconnected from server');
      _stopPointerMode();
      Get.offNamed('/qr_scan');
    }
  }

  void _handleLaserModeChange(bool enabled) {
    if (enabled) {
      _startPointerMode();
    } else {
      _stopPointerMode();
    }
  }

  Future<void> connectWithCode(String input) async {
    try {
      print('Attempting to connect with input: $input');

      if (!input.startsWith('{')) {
        throw Exception('잘못된 연결 데이터 형식');
      }

      final connectionData = json.decode(input);
      print('Parsed connection data: $connectionData');

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

  void _startPointerMode() {
    if (_isPointerActive) return;
    _isPointerActive = true;

    // 센서 초기화 및 보정
    _startCalibration();

    // 자이로스코프 시작
    _gyroSubscription = gyroscopeEvents.listen(_handleGyroscope);

    // 자기장 센서 시작
    _magnetSubscription = magnetometerEvents.listen(_handleMagnetometer);

    // 가속도계 시작
    _accelSubscription = accelerometerEvents.listen(_handleAccelerometer);

    // 업데이트 타이머 시작
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: UPDATE_INTERVAL_MS),
      (_) => _updatePointerPosition(),
    );
  }

  void _startCalibration() {
    isCalibrating.value = true;
    calibrationProgress.value = 0;
    _calibrationData.clear();
    _baseOrientation = null;

    // 보정 데이터 수집
    Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (_calibrationData.length >= CALIBRATION_SAMPLES) {
        _finishCalibration();
        timer.cancel();
        return;
      }

      calibrationProgress.value = (_calibrationData.length / CALIBRATION_SAMPLES * 100).round();
    });
  }

  void _finishCalibration() {
    if (_calibrationData.isEmpty) return;

    // 평균 방향 계산
    double sumX = 0, sumY = 0, sumZ = 0;
    for (var data in _calibrationData) {
      sumX += data.x;
      sumY += data.y;
      sumZ += data.z;
    }

    _baseOrientation = SensorData(
      sumX / _calibrationData.length,
      sumY / _calibrationData.length,
      sumZ / _calibrationData.length,
    );

    isCalibrating.value = false;
    _pointerState.reset();
  }

  void _handleGyroscope(GyroscopeEvent event) {
    if (!_isPointerActive || isCalibrating.value) return;

    final dt = DateTime.now().difference(_lastUpdateTime).inMicroseconds / 1000000;
    _lastUpdateTime = DateTime.now();

    // 자이로스코프 데이터를 각도 변화로 변환
    final dx = event.y * dt * POINTER_SENSITIVITY; // 좌우 움직임
    final dy = -event.x * dt * POINTER_SENSITIVITY; // 상하 움직임

    // 칼만 필터 적용
    _updateKalmanFilter(dx, dy, dt);
  }

  void _handleMagnetometer(MagnetometerEvent event) {
    if (!_isPointerActive || isCalibrating.value) return;

    if (_baseOrientation == null) {
      _calibrationData.add(SensorData(event.x, event.y, event.z));
      return;
    }

    // 방향 보정에 사용
    final currentOrientation = SensorData(event.x, event.y, event.z);
    final angle = _baseOrientation!.angleTo(currentOrientation);

    if (angle > pi / 2) {
      _startCalibration(); // 큰 방향 변화 감지시 재보정
    }
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    if (!_isPointerActive || isCalibrating.value) return;

    // 중력 방향을 이용한 절대 각도 계산
    final pitch = atan2(event.x, sqrt(event.y * event.y + event.z * event.z));
    final roll = atan2(event.y, event.z);

    _pointerState.pitch = pitch * 180 / pi;
    _pointerState.roll = roll * 180 / pi;
  }

  void _updateKalmanFilter(double dx, double dy, double dt) {
    // 예측 단계
    _kalmanUncertaintyX += _kalmanQ * dt;
    _kalmanUncertaintyY += _kalmanQ * dt;

    // 업데이트 단계
    final kx = _kalmanUncertaintyX / (_kalmanUncertaintyX + _kalmanR);
    final ky = _kalmanUncertaintyY / (_kalmanUncertaintyY + _kalmanR);

    _kalmanAngleX += kx * (dx - _kalmanAngleX);
    _kalmanAngleY += ky * (dy - _kalmanAngleY);

    _kalmanUncertaintyX *= (1 - kx);
    _kalmanUncertaintyY *= (1 - ky);

    // 각도 제한
    _kalmanAngleX = _kalmanAngleX.clamp(-MAX_ANGLE_DEG, MAX_ANGLE_DEG);
    _kalmanAngleY = _kalmanAngleY.clamp(-MAX_ANGLE_DEG, MAX_ANGLE_DEG);
  }

  void _updatePointerPosition() {
    if (!_isPointerActive || isCalibrating.value) return;

    // 각도를 화면 좌표로 변환
    final newX = 0.5 + (_kalmanAngleX / MAX_ANGLE_DEG) * 0.5;
    final newY = 0.5 + (_kalmanAngleY / MAX_ANGLE_DEG) * 0.5;

    // 부드러운 움직임을 위한 보간
    _pointerState.x = _pointerState.x * SMOOTHING_FACTOR + newX * (1 - SMOOTHING_FACTOR);
    _pointerState.y = _pointerState.y * SMOOTHING_FACTOR + newY * (1 - SMOOTHING_FACTOR);

    // 좌표 범위 제한
    _pointerState.x = _pointerState.x.clamp(0.0, 1.0);
    _pointerState.y = _pointerState.y.clamp(0.0, 1.0);

    _sendPointerPosition();
  }

  void _sendPointerPosition() {
    if (!isConnected.value) return;

    _udpService.sendCommand({
      'type': 'mouse_move',
      'x': _pointerState.x,
      'y': _pointerState.y,
      'is_laser': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _stopPointerMode() {
    _isPointerActive = false;
    _gyroSubscription?.cancel();
    _magnetSubscription?.cancel();
    _accelSubscription?.cancel();
    _updateTimer?.cancel();
    _pointerState.reset();
  }

  // 사용자 인터페이스 명령
  void toggleLaserMode() {
    isLaserMode.toggle();
    print('Toggling laser mode: ${isLaserMode.value}');
  }

  void togglePresentationMode() {
    if (!isConnected.value) return;
    isPresentationMode.toggle();
    print('Toggling presentation mode: ${isPresentationMode.value}');
    _sendKeyCommand(isPresentationMode.value ? 'f5' : 'esc');
  }

  void nextSlide() => _sendKeyCommand('right');
  void previousSlide() => _sendKeyCommand('left');
  void toggleBlackScreen() => _sendKeyCommand('b');
  void toggleWhiteScreen() => _sendKeyCommand('w');

  void sendClick(String type) {
    if (!isConnected.value) return;
    _resetInactivityTimer();

    _udpService.sendCommand({
      'type': 'mouse_click',
      'click_type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendKeyCommand(String key) {
    if (!isConnected.value) return;
    _resetInactivityTimer();

    _udpService.sendCommand({
      'type': 'keyboard',
      'key': key,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 10), disconnect);
  }

  void _resetInactivityTimer() {
    _startInactivityTimer();
  }

  void disconnect() {
    if (!isConnected.value) return;

    _udpService.sendCommand({
      'type': 'disconnect',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _stopPointerMode();
    _udpService.disconnect();
    isConnected.value = false;
    isPresentationMode.value = false;
    isLaserMode.value = false;
  }

  @override
  void onClose() {
    print('Closing RemoteControlController');
    WakelockPlus.disable();
    _inactivityTimer?.cancel();
    _updateTimer?.cancel();
    _stopPointerMode();
    disconnect();
    super.onClose();
  }
}
