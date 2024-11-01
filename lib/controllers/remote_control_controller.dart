import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:convert';

import '../services/udp_service.dart' as udp;
import '../models/vector_2d.dart';
import '../models/accelerometer_data.dart';
import '../enums/control_mode.dart';
import '../constants/controller_constants.dart';

class RemoteControlController extends GetxController {
  final udp.UDPService _udpService = Get.find<udp.UDPService>();

  // 상태 관리
  final isConnected = false.obs;
  final controlMode = ControlMode.none.obs;
  final mousePosition = Rx<Point>({'x': 0.0, 'y': 0.0});
  bool get isPresentationMode => controlMode.value == ControlMode.presentation;
  bool get isLaserMode => controlMode.value == ControlMode.laser;

  // 마우스 이동 관련 변수
  final Vector2D _velocity = Vector2D(0, 0);
  final Queue<AccelerometerData> _accelerometerQueue = Queue<AccelerometerData>();
  Timer? _mouseMoveTimer;
  Timer? _velocityDecayTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 활성화 관리
  Timer? _inactivityTimer;
  bool _isAccelerometerActive = false;
  DateTime _lastUpdateTime = DateTime.now();

  // 마우스 감도 조절
  final double _currentSensitivityX = ControllerConstants.baseSensitivityX;
  final double _currentSensitivityY = ControllerConstants.baseSensitivityY;

  bool _isConnecting = false; // 연결 시도 중 상태 추가

  @override
  void onInit() {
    super.onInit();
    _initializeController();
    _setupEventListeners();
  }

  void _initializeController() {
    WakelockPlus.enable();
    _startInactivityTimer();
    _startVelocityDecayTimer();
  }

  void _setupEventListeners() {
    ever(_udpService.isConnected, _handleConnectionStateChange);
    ever(_udpService.connectionState, _handleDetailedConnectionState);
  }

  void _handleConnectionStateChange(bool connected) {
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
  }

  void _handleDetailedConnectionState(udp.ConnectionState state) {
    switch (state) {
      case udp.ConnectionState.connecting:
        print('Connecting to server...');
        break;
      case udp.ConnectionState.authenticating:
        print('Authenticating...');
        break;
      case udp.ConnectionState.connected:
        print('Connection established');
        break;
      case udp.ConnectionState.disconnected:
        print('Connection lost');
        break;
    }
  }

  Future<void> connectWithCode(String input) async {
    if (_isConnecting) {
      print('Already attempting to connect...');
      return;
    }

    try {
      _isConnecting = true;
      print('Attempting to connect with input: $input');

      final Map<String, dynamic> connectionData = _parseConnectionData(input);
      await _establishConnection(connectionData);
    } catch (e) {
      _handleConnectionError(e);
    } finally {
      _isConnecting = false;
    }
  }

  Map<String, dynamic> _parseConnectionData(String input) {
    if (!input.startsWith('{')) {
      throw Exception('잘못된 연결 데이터 형식');
    }
    final data = json.decode(input);
    print('Parsed connection data: $data');
    return data;
  }

  // 연결 시도 로직 분리
  Future<void> _establishConnection(Map<String, dynamic> data) async {
    try {
      await _udpService.connectToServer(
        data['ip'],
        data['port'],
        data['code'].toString(),
      );
    } catch (e) {
      print('Connection establishment error: $e');
      rethrow;
    }
  }

  Future<void> _handleConnectionError(dynamic error) async {
    print('Connection error: $error');

    // 에러 메시지 표시 및 사용자 응답 대기
    final shouldRetry = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('연결 오류'),
        content: Text('서버 연결에 실패했습니다: ${error.toString()}\n다시 시도하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('다시 시도'),
          ),
        ],
      ),
      barrierDismissible: false, // 배경 탭으로 닫기 방지
    );

    if (shouldRetry == true) {
      // QR 스캔 뷰로 돌아가기
      Get.offNamed('/qr_scan');
    }
  }

  void _startAccelerometer() {
    if (_isAccelerometerActive) return;

    _accelerometerSubscription = accelerometerEvents.listen(_handleAccelerometerEvent);
    _isAccelerometerActive = true;
    print('Accelerometer activated');
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    if (!isConnected.value || !_isAccelerometerActive) return;

    final now = DateTime.now();
    final deltaTime = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    _lastUpdateTime = now;

    if (_isUnderThreshold(event)) return;

    _updateAccelerometerQueue(event, now);
    _updateVelocity(deltaTime);
    _sendMouseMoveCommand();
  }

  bool _isUnderThreshold(AccelerometerEvent event) {
    return event.x.abs() < ControllerConstants.accelerometerThreshold && event.y.abs() < ControllerConstants.accelerometerThreshold;
  }

  void _updateAccelerometerQueue(AccelerometerEvent event, DateTime timestamp) {
    _accelerometerQueue.add(AccelerometerData(
      Vector2D(event.x, event.y),
      timestamp,
    ));

    if (_accelerometerQueue.length > ControllerConstants.queueMaxLength) {
      _accelerometerQueue.removeFirst();
    }
  }

  void _updateVelocity(double deltaTime) {
    if (_accelerometerQueue.isEmpty) return;

    final avgAcceleration = _calculateWeightedAverage();
    _applyVelocityChange(avgAcceleration, deltaTime);
  }

  Vector2D _calculateWeightedAverage() {
    var avgAcceleration = Vector2D(0, 0);
    var totalWeight = 0.0;

    _accelerometerQueue.toList().asMap().forEach((index, data) {
      final weight = (index + 1) / _accelerometerQueue.length;
      totalWeight += weight;
      avgAcceleration.x += data.acceleration.x * weight;
      avgAcceleration.y += data.acceleration.y * weight;
    });

    return Vector2D(
      avgAcceleration.x / totalWeight,
      avgAcceleration.y / totalWeight,
    );
  }

  void _applyVelocityChange(Vector2D acceleration, double deltaTime) {
    _velocity.x += (acceleration.x * _currentSensitivityX * deltaTime - _velocity.x) * ControllerConstants.smoothingFactor;
    _velocity.y += (acceleration.y * _currentSensitivityY * deltaTime - _velocity.y) * ControllerConstants.smoothingFactor;
  }

  void _startVelocityDecayTimer() {
    _velocityDecayTimer?.cancel();
    _velocityDecayTimer = Timer.periodic(
      const Duration(milliseconds: ControllerConstants.mouseMoveInterval),
      (_) => _applyVelocityDecay(),
    );
  }

  void _applyVelocityDecay() {
    _velocity.x *= ControllerConstants.velocityDecay;
    _velocity.y *= ControllerConstants.velocityDecay;
  }

  void updateMousePosition(double x, double y) {
    if (!isConnected.value) return;

    final normalizedPosition = _normalizePosition(x, y);
    mousePosition.value = normalizedPosition;

    _sendMouseMoveAbsolute(normalizedPosition);
  }

  Map<String, double> _normalizePosition(double x, double y) {
    return {
      'x': math.min(1.0, math.max(0.0, x / Get.width)),
      'y': math.min(1.0, math.max(0.0, y / Get.height)),
    };
  }

  void _sendMouseMoveAbsolute(Map<String, double> position) {
    _udpService.sendCommand({
      'type': 'mouse_move',
      'x': position['x'],
      'y': position['y'],
      'is_laser': isLaserMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendMouseMoveCommand() {
    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(
      const Duration(milliseconds: ControllerConstants.mouseMoveInterval),
      () => _sendMouseMoveRelative(),
    );
  }

  void _sendMouseMoveRelative() {
    if (!isConnected.value) return;

    _udpService.sendCommand({
      'type': 'mouse_move_relative',
      'dx': -_velocity.x,
      'dy': _velocity.y,
      'is_laser': isLaserMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // 타이머 관리
  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      const Duration(minutes: ControllerConstants.inactivityTimeout),
      disconnect,
    );
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
  void nextSlide() => sendKeyCommand('right');
  void previousSlide() => sendKeyCommand('left');
  void toggleBlackScreen() => sendKeyCommand('b');
  void toggleWhiteScreen() => sendKeyCommand('w');

  void togglePresentationMode() {
    if (!isConnected.value) return;

    if (controlMode.value == ControlMode.presentation) {
      controlMode.value = ControlMode.none;
      sendKeyCommand('esc');
    } else {
      controlMode.value = ControlMode.presentation;
      sendKeyCommand('f5');
    }

    print('Presentation mode: ${controlMode.value}');
  }

  void toggleLaserMode() {
    if (controlMode.value == ControlMode.laser) {
      controlMode.value = ControlMode.none;
      _startAccelerometer();
    } else {
      controlMode.value = ControlMode.laser;
      _stopAccelerometer();
    }

    print('Laser mode: ${controlMode.value}');
  }

  void _stopAccelerometer() {
    _accelerometerSubscription?.cancel();
    _isAccelerometerActive = false;
    _velocity.x = 0;
    _velocity.y = 0;
    _accelerometerQueue.clear();
    print('Accelerometer deactivated');
  }

  void disconnect() {
    if (!isConnected.value) return;

    print('Disconnecting from server');
    _udpService.sendCommand({
      'type': 'disconnect',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _cleanup();
  }

  void _cleanup() {
    _udpService.disconnect();
    isConnected.value = false;
    controlMode.value = ControlMode.none;
    _stopAccelerometer();
    _velocity.x = 0;
    _velocity.y = 0;
    _accelerometerQueue.clear();
  }

  @override
  void onClose() {
    print('Closing RemoteControlController');
    WakelockPlus.disable();
    _inactivityTimer?.cancel();
    _mouseMoveTimer?.cancel();
    _velocityDecayTimer?.cancel();
    _stopAccelerometer();
    disconnect();
    super.onClose();
  }
}

typedef Point = Map<String, double>;
