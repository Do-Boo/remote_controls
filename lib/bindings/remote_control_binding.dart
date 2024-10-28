import 'package:get/get.dart';
import '../controllers/remote_control_controller.dart';
import '../services/udp_service.dart';

class RemoteControlBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => UdpService(), fenix: true);
    Get.lazyPut(() => RemoteControlController(), fenix: true);
  }
}
