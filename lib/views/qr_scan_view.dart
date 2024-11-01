import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../controllers/remote_control_controller.dart';

class QRScanView extends GetView<RemoteControlController> {
  QRScanView({super.key});

  final MobileScannerController scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  void _handleScannedData(String data, MobileScannerController scannerController) async {
    try {
      scannerController.stop(); // 스캔 일시 중지
      print('QRScanView: Raw data received: $data');
      await controller.connectWithCode(data);
    } catch (e) {
      print('QRScanView connection error: $e');
      scannerController.start(); // 스캔 재개
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR 코드 스캔'),
        actions: [
          // 플래시 토글 버튼
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => scannerController.toggleTorch(),
          ),
          // 카메라 전환 버튼
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: scannerController,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _handleScannedData(barcode.rawValue!, scannerController);
                    break;
                  }
                }
              },
            ),
          ),
          // 스캔 가이드 텍스트
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            width: double.infinity,
            child: const Column(
              children: [
                Text(
                  'QR 코드를 스캔하세요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '화면에 표시된 QR 코드를 프레임 안에 맞춰주세요',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void dispose() {
    scannerController.dispose();
  }
}
