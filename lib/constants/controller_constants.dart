class ControllerConstants {
  // 가속도계 설정
  static const double accelerometerThreshold = 0.3;
  static const double baseSensitivityX = 12.0;
  static const double baseSensitivityY = 12.0;
  static const double smoothingFactor = 0.4;
  static const double velocityDecay = 0.95;

  // 큐 설정
  static const int queueMaxLength = 8;

  // 타이머 설정
  static const int mouseMoveInterval = 16; // milliseconds
  static const int inactivityTimeout = 10; // minutes
}
