import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../controllers/remote_control_controller.dart';

class QRScanView extends StatefulWidget {
  const QRScanView({super.key});

  @override
  State<QRScanView> createState() => _QRScanViewState();
}

class _QRScanViewState extends State<QRScanView> {
  late MobileScannerController scannerController;
  bool isFlashOn = false;
  bool isProcessingCode = false; // 스캔 처리 중 상태 추가
  final TextEditingController codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    scannerController.dispose();
    codeController.dispose();
    super.dispose();
  }

  void connectWithCode(String rawData) async {
    if (isProcessingCode || rawData.isEmpty) return; // 처리 중이면 무시

    setState(() {
      isProcessingCode = true; // 처리 시작
    });

    try {
      print('QRScanView: Raw data received: $rawData');
      if (rawData.startsWith('{')) {
        final jsonData = json.decode(rawData);
        print('QRScanView: Parsed JSON data: $jsonData');
      }

      final controller = Get.find<RemoteControlController>();
      await controller.connectWithCode(rawData); // await 추가
    } catch (e) {
      print('QRScanView connection error: $e');
      Get.snackbar(
        '연결 오류',
        '연결 중 오류가 발생했습니다.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      setState(() {
        isProcessingCode = false; // 처리 완료
      });
    }
  }

  void showCodeInputDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('연결 코드 입력'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            hintText: '6자리 코드를 입력하세요',
            border: OutlineInputBorder(),
          ),
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(letterSpacing: 8.0),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (codeController.text.length == 6) {
                Get.back();
                connectWithCode(codeController.text.toUpperCase());
              } else {
                Get.snackbar(
                  '오류',
                  '6자리 코드를 입력해주세요',
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            },
            child: const Text('연결'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR 코드 스캔'),
        actions: [
          // 플래시 버튼
          IconButton(
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () async {
              await scannerController.toggleTorch();
              setState(() {
                isFlashOn = !isFlashOn;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: scannerController,
              onDetect: (capture) {
                try {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    final String? rawValue = barcode.rawValue;
                    if (rawValue != null) {
                      print('Scanned QR data: $rawValue');
                      connectWithCode(rawValue);
                    }
                  }
                } catch (e) {
                  print('QR Scan Error: $e');
                  Get.snackbar(
                    'Error',
                    'QR 코드 스캔 중 오류가 발생했습니다',
                    snackPosition: SnackPosition.BOTTOM,
                  );
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text(
                  'PC에 표시된 QR 코드를 스캔하세요',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '또는',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: showCodeInputDialog,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 45),
                  ),
                  child: const Text('코드 직접 입력'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
