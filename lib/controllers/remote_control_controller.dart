import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/websocket_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:convert';

class RemoteControlController extends GetxController {
  final WebSocketService _wsService = Get.find<WebSocketService>();

  // 상태 관리
  final isConnected = false.obs;
  final isPresentationMode = false.obs;
  final isLaserMode = false.obs;
  final mousePosition = Rx<Point>({'x': 0.0, 'y': 0.0});

  // 자이로 센서 관련 변수
  final gyroEnabled = false.obs;
  final sensitivity = 2.0.obs;
  final isCalibrating = false.obs;

  StreamSubscription? _gyroSubscription;
  Vector3? _lastGyroEvent;
  Vector3? _calibrationOffset;

  // 상수
  static const _gyroThreshold = 0.05;
  static const _updateInterval = Duration(milliseconds: 16);

  Timer? _mouseMoveTimer;

  @override
  void onInit() {
    super.onInit();
    // 연결 상태가 변경될 때마다 화면 전환
    ever(isConnected, (bool connected) {
      if (connected) {
        print('Connected to server! Navigating to RemoteControlView');
        Get.toNamed('/remote_control'); // 수정된 부분
      }
    });
    ever(_wsService.isConnected, _handleConnectionChange);
    ever(gyroEnabled, _handleGyroModeChange);
    _initGyroscope();
  }

  void _handleConnectionChange(bool connected) {
    isConnected.value = connected;
    if (connected) {
      Get.snackbar(
        '연결 성공',
        '리모컨이 연결되었습니다.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      Get.snackbar(
        '연결 해제',
        '리모컨 연결이 해제되었습니다.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _handleGyroModeChange(bool enabled) {
    if (enabled) {
      _calibrationOffset = null;
      _startCalibration();
      Get.snackbar(
        '자이로 모드',
        '기기를 평평하게 든 상태에서 잠시 기다려주세요.',
        duration: const Duration(seconds: 3),
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      _calibrationOffset = null;
    }
  }

  void _startCalibration() {
    isCalibrating.value = true;
    Vector3 sum = const Vector3(0, 0, 0);
    int samples = 0;

    Timer(const Duration(seconds: 2), () {
      if (samples > 0) {
        _calibrationOffset = Vector3(
          sum.x / samples,
          sum.y / samples,
          sum.z / samples,
        );
      }
      isCalibrating.value = false;
    });
  }

  void _initGyroscope() {
    try {
      _gyroSubscription = gyroscopeEvents.listen(
        (GyroscopeEvent event) {
          if (!gyroEnabled.value || !isConnected.value) return;

          if (isCalibrating.value) return;

          Vector3 currentEvent = Vector3(event.x, event.y, event.z);

          if (_calibrationOffset != null) {
            currentEvent = Vector3(
              currentEvent.x - _calibrationOffset!.x,
              currentEvent.y - _calibrationOffset!.y,
              currentEvent.z - _calibrationOffset!.z,
            );
          }

          if (_lastGyroEvent == null) {
            _lastGyroEvent = currentEvent;
            return;
          }

          if (currentEvent.x.abs() < _gyroThreshold && currentEvent.y.abs() < _gyroThreshold) return;

          double currentX = mousePosition.value['x'] ?? 0.0;
          double currentY = mousePosition.value['y'] ?? 0.0;

          double deltaX = -currentEvent.y * sensitivity.value;
          double deltaY = currentEvent.x * sensitivity.value;

          double newX = (currentX + deltaX).clamp(0.0, 1.0);
          double newY = (currentY + deltaY).clamp(0.0, 1.0);

          mousePosition.value = {'x': newX, 'y': newY};

          _mouseMoveTimer?.cancel();
          _mouseMoveTimer = Timer(_updateInterval, () {
            _wsService.sendCommand({
              'type': 'mouse_move',
              'x': mousePosition.value['x'],
              'y': mousePosition.value['y'],
              'is_laser': isLaserMode.value,
              'is_gyro': true,
            });
          });

          _lastGyroEvent = currentEvent;
        },
        onError: (error) {
          print('Gyroscope error: $error');
          gyroEnabled.value = false;
          Get.snackbar(
            '센서 오류',
            '자이로스코프를 사용할 수 없습니다.',
            snackPosition: SnackPosition.BOTTOM,
          );
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('Gyroscope initialization error: $e');
      gyroEnabled.value = false;
      Get.snackbar(
        '센서 오류',
        '자이로스코프를 사용할 수 없습니다.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> connectWithCode(String code) async {
    try {
      print('Attempting to connect with code: $code');

      // QR 코드에서 받은 데이터로 연결
      final qrData = json.decode(code);
      final ip = qrData['ip'];
      final port = qrData['port'];
      final serverCode = qrData['code'];

      await _wsService.connectToServer(ip, port, serverCode);
      isConnected.value = true;
      print('Successfully connected to server');
    } catch (e) {
      print('Connection error: $e');
      isConnected.value = false;
      rethrow;
    }
  }

  void updateMousePosition(Offset position, Size screenSize) {
    if (!isConnected.value || gyroEnabled.value) return;

    mousePosition.value = {'x': position.dx / screenSize.width, 'y': position.dy / screenSize.height};

    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(_updateInterval, () {
      _wsService.sendCommand({
        'type': 'mouse_move',
        'x': mousePosition.value['x'],
        'y': mousePosition.value['y'],
        'is_laser': isLaserMode.value,
        'is_gyro': false,
      });
    });
  }

  void sendClick(String type) {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'mouse_click',
      'click_type': type,
    });
  }

  void sendKeyCommand(String key) {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'keyboard',
      'key': key,
    });
  }

  void nextSlide() {
    sendKeyCommand('right_arrow');
  }

  void previousSlide() {
    sendKeyCommand('left_arrow');
  }

  void toggleBlackScreen() {
    sendKeyCommand('b');
  }

  void toggleWhiteScreen() {
    sendKeyCommand('w');
  }

  void togglePresentationMode() {
    isPresentationMode.toggle();
    _wsService.sendCommand({
      'type': 'presentation_mode',
      'enabled': isPresentationMode.value,
    });
  }

  void toggleLaserMode() {
    isLaserMode.toggle();
  }

  void startDrag() {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'mouse_drag',
      'action': 'start',
    });
  }

  void endDrag() {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'mouse_drag',
      'action': 'end',
    });
  }

  void adjustVolume(double delta) {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'volume',
      'delta': delta,
    });
  }

  void disconnect() {
    if (!isConnected.value) return;

    _wsService.sendCommand({
      'type': 'disconnect',
    });
    isConnected.value = false;
    isPresentationMode.value = false;
    isLaserMode.value = false;
    gyroEnabled.value = false;
  }

  void toggleGyroMode() {
    gyroEnabled.toggle();
    if (!gyroEnabled.value) {
      Get.snackbar(
        '자이로 모드',
        '자이로 모드가 비활성화되었습니다.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void adjustSensitivity(double value) {
    sensitivity.value = value.clamp(0.5, 5.0);
  }

  @override
  void onClose() {
    _mouseMoveTimer?.cancel();
    _gyroSubscription?.cancel();
    disconnect();
    super.onClose();
  }
}

typedef Point = Map<String, double>;

class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);

  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator /(double scalar) => Vector3(x / scalar, y / scalar, z / scalar);
}
