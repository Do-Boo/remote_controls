import 'package:get/get.dart';
import '../controllers/remote_control_controller.dart';
import '../services/websocket_service.dart';

class RemoteControlBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => WebSocketService(), fenix: true);
    Get.lazyPut(() => RemoteControlController(), fenix: true);
  }
}
