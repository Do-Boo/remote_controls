import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/websocket_service.dart';
import 'dart:convert';

class RemoteControlController extends GetxController {
  final WebSocketService _wsService = Get.find<WebSocketService>();

  // 상태 관리
  final isConnected = false.obs;
  final isPresentationMode = false.obs;
  final isLaserMode = false.obs;
  final mousePosition = Rx<Point>({'x': 0.0, 'y': 0.0});

  // 마우스 이동 관련 상수
  static const double baseMultiplier = 10.0; // 기본 이동 배율
  static const double smoothness = 0.3; // 부드러움 계수
  static const double minMovementThreshold = 0.5; // 최소 이동 감지 거리
  static const _updateInterval = Duration(milliseconds: 16); // 60 FPS
  static const _queueMaxLength = 5; // 이동 평균 계산용 큐 길이

  // 마우스 이동 관련 변수
  DateTime? _lastUpdateTime;
  double _velocityX = 0;
  double _velocityY = 0;
  Offset? _lastPosition;
  final Queue<Offset> _movementQueue = Queue<Offset>();
  Timer? _mouseMoveTimer;

  @override
  void onInit() {
    super.onInit();
    ever(isConnected, (bool connected) {
      if (connected) {
        print('Connected to server! Navigating to RemoteControlView');
        Get.toNamed('/remote_control');
      }
    });
    ever(_wsService.isConnected, _handleConnectionChange);
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
      _initializeMovement(position);
      return;
    }

    final now = DateTime.now();
    _lastUpdateTime = now;

    final dx = (position.dx - _lastPosition!.dx);
    final dy = (position.dy - _lastPosition!.dy);

    if (dx.abs() < minMovementThreshold && dy.abs() < minMovementThreshold) return;

    _updateMovementQueue(Offset(dx, dy));
    final avgMovement = _calculateAverageMovement();

    final targetVelocityX = avgMovement.dx * baseMultiplier * 3;
    final targetVelocityY = avgMovement.dy * baseMultiplier * 3;

    _velocityX += (targetVelocityX - _velocityX) * smoothness;
    _velocityY += (targetVelocityY - _velocityY) * smoothness;

    _sendMouseMoveCommand(now);
    _lastPosition = position;
  }

  void _initializeMovement(Offset position) {
    _lastPosition = position;
    _lastUpdateTime = DateTime.now();
    _velocityX = 0;
    _velocityY = 0;
    _movementQueue.clear();
  }

  void _updateMovementQueue(Offset movement) {
    _movementQueue.add(movement);
    if (_movementQueue.length > _queueMaxLength) {
      _movementQueue.removeFirst();
    }
  }

  Offset _calculateAverageMovement() {
    double avgDx = 0;
    double avgDy = 0;
    for (var offset in _movementQueue) {
      avgDx += offset.dx;
      avgDy += offset.dy;
    }
    return Offset(avgDx / _movementQueue.length, avgDy / _movementQueue.length);
  }

  void _sendMouseMoveCommand(DateTime timestamp) {
    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(_updateInterval, () {
      _wsService.sendCommand({
        'type': 'mouse_move_relative',
        'dx': _velocityX,
        'dy': _velocityY,
        'is_laser': isLaserMode.value,
        'timestamp': timestamp.millisecondsSinceEpoch,
      });
    });
  }

  void _resetMovement() {
    _lastPosition = null;
    _lastUpdateTime = null;
    _velocityX = 0;
    _velocityY = 0;
    _movementQueue.clear();
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
    _wsService.sendCommand({
      'type': 'keyboard',
      'key': isPresentationMode.value ? 'f5' : 'esc',
    });
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
    _wsService.disconnect();
    isConnected.value = false;
    isPresentationMode.value = false;
    isLaserMode.value = false;
  }

  @override
  void onClose() {
    _mouseMoveTimer?.cancel();
    _resetMovement();
    disconnect();
    super.onClose();
  }
}

typedef Point = Map<String, double>;
