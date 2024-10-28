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
  final sensitivity = 1.0.obs; // 기본값을 더 낮게 설정
  final isCalibrating = false.obs;

  StreamSubscription? _gyroSubscription;
  Vector3? _lastGyroEvent;
  Vector3? _calibrationOffset;

  // 상수
  static const _gyroThreshold = 0.05;
  static const _updateInterval = Duration(milliseconds: 16);

  Timer? _mouseMoveTimer;

  Offset? _lastPosition; // 마지막 터치 위치 저장용 변수 추가

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

          // 감도를 더 낮추고 Y축 반전
          double deltaX = -currentEvent.y * (sensitivity.value * 0.3); // 감도 낮춤
          double deltaY = -currentEvent.x * (sensitivity.value * 0.3); // Y축 반전

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
        },
        onError: (error) {
          print('Gyroscope error: $error');
          gyroEnabled.value = false;
          Get.snackbar(
            '센서 오류',
            '자이로 센서를 사용할 수 없습니다.',
            snackPosition: SnackPosition.BOTTOM,
          );
        },
      );
    } catch (e) {
      print('Gyroscope initialization error: $e');
    }
  }

  Future<void> connectWithCode(String input) async {
    try {
      print('Attempting to connect with input: $input');

      Map<String, dynamic> connectionData;

      // JSON 형식인 경우 (QR 코드 스캔)
      if (input.startsWith('{')) {
        connectionData = json.decode(input);
      }
      // 6자리 코드인 경 (수동 입력)
      else {
        // 서버에서 받은 IP와 포트 사용
        connectionData = {
          'code': input,
          'ip': '192.168.0.x', // 실제 서버 IP로 변경 필요
          'port': 8080 // 실제 서버 포트로 변경 필요
        };
      }

      print('Connecting with data: $connectionData');

      await _wsService.connectToServer(connectionData['ip'].toString(), connectionData['port'] as int, connectionData['code'].toString());

      if (_wsService.isConnected.value) {
        isConnected.value = true;
        print('Successfully connected to server');
        Get.snackbar(
          '연결 성공',
          '서버에 연결되었습니다.',
          snackPosition: SnackPosition.BOTTOM,
        );
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

  void updateMousePosition(Offset position, Size screenSize) {
    if (!isConnected.value) return;

    if (_lastPosition == null) {
      _lastPosition = position;
      return;
    }

    // 이전 위치와의 차이를 계산
    final deltaX = (position.dx - _lastPosition!.dx) / screenSize.width;
    final deltaY = (position.dy - _lastPosition!.dy) / screenSize.height;

    // 현재 마우스 위치에서 델타값을 더함
    final newX = (mousePosition.value['x']! + (deltaX * 1.5)).clamp(0.0, 1.0); // 감도 조절을 위해 1.5 곱함
    final newY = (mousePosition.value['y']! + (deltaY * 1.5)).clamp(0.0, 1.0);

    // 위치 업데이트
    mousePosition.value = {'x': newX, 'y': newY};
    _lastPosition = position;

    // 즉시 전송
    _wsService.sendCommand({
      'type': 'mouse_move',
      'x': newX,
      'y': newY,
      'is_laser': isLaserMode.value,
      'is_gyro': false,
      'immediate': true,
    });
  }

  void startDrag() {
    _lastPosition = null; // 드래그 시작시 마지막 위치 초기화
    print('Started dragging');
  }

  void endDrag() {
    _lastPosition = null; // 드래그 종료시 마지막 위치 초기화
    print('Ended dragging');
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
    print('Sending key command: $key');
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': key,
    });
  }

  void nextSlide() {
    if (!isConnected.value) return;
    print('Sending next slide command');
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': 'right', // 'right_arrow' 대신 'right' 사용
    });
  }

  void previousSlide() {
    if (!isConnected.value) return;
    print('Sending previous slide command');
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': 'left', // 'left_arrow' 대신 'left' 사용
    });
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
    if (isPresentationMode.value) {
      // 프레젠테이션 시작 (F5)
      _wsService.sendCommand({
        'type': 'keyboard',
        'key': 'f5',
      });
    } else {
      // 프레젠테이션 종료 (ESC)
      _wsService.sendCommand({
        'type': 'keyboard',
        'key': 'esc',
      });
    }
  }

  void toggleLaserMode() {
    isLaserMode.toggle();
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
    _wsService.disconnect(); // WebSocket 연결 종료
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
