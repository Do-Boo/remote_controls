import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:presentation_remote_controls/services/websocket_service.dart';
import 'views/qr_scan_view.dart';
import 'views/remote_control_view.dart';
import 'bindings/remote_control_binding.dart';

void main() async {
  try {
    // Flutter 바인딩 초기화
    WidgetsFlutterBinding.ensureInitialized();

    // GetX 서비스 초기화
    final binding = RemoteControlBinding();
    Get.put(WebSocketService());

    binding.dependencies();
    runApp(const MyApp());
  } catch (e) {
    print('Initialization error: $e');
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Remote Control',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      initialBinding: RemoteControlBinding(),
      home: const QRScanView(),
      getPages: [
        GetPage(
          name: '/remote_control',
          page: () => const RemoteControlView(),
          binding: RemoteControlBinding(),
        ),
      ],
    );
  }
}
