import 'vector_2d.dart';

class AccelerometerData {
  final Vector2D acceleration;
  final DateTime timestamp;

  AccelerometerData(this.acceleration, this.timestamp);

  @override
  String toString() => 'AccelerometerData(acceleration: $acceleration, timestamp: $timestamp)';
}
