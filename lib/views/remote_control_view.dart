// lib/views/remote_control_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/remote_control_controller.dart';

class RemoteControlView extends GetView<RemoteControlController> {
  const RemoteControlView({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async {
        controller.disconnect();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            '리모컨',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            // 연결 상태 표시
            Obx(() => Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      controller.isConnected.value ? '연결됨' : '연결 안됨',
                      style: TextStyle(
                        color: controller.isConnected.value ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )),
            // 연결 해제 버튼
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: () {
                HapticFeedback.mediumImpact();
                controller.disconnect();
                Get.back();
              },
              tooltip: '연결 해제',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 메인 제어 영역
              Expanded(
                child: GestureDetector(
                  onPanUpdate: (details) {
                    if (controller.isLaserMode) {
                      // 마우스 위치 업데이트
                      final dx = details.delta.dx;
                      final dy = details.delta.dy;
                      controller.updateMousePosition(dx, dy);
                    }
                  },
                  onTapUp: (details) {
                    HapticFeedback.mediumImpact();
                    if (controller.isLaserMode) {
                      controller.sendClick('left');
                    } else {
                      if (details.localPosition.dx < screenSize.width / 2) {
                        controller.previousSlide();
                      } else {
                        controller.nextSlide();
                      }
                    }
                  },
                  onDoubleTap: () {
                    if (controller.isLaserMode) {
                      HapticFeedback.mediumImpact();
                      controller.sendClick('double');
                    }
                  },
                  onLongPress: () {
                    if (controller.isLaserMode) {
                      HapticFeedback.heavyImpact();
                      controller.sendClick('right');
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {},
                        splashColor: Colors.grey.withOpacity(0.3),
                        highlightColor: Colors.grey.withOpacity(0.1),
                        child: Obx(() => controller.isLaserMode
                            ? Stack(
                                children: [
                                  const Center(
                                    child: Text(
                                      '트랙패드 영역',
                                      style: TextStyle(
                                        color: Colors.white30,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 10,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Text(
                                        '길게 누르기: 우클릭 / 더블 탭: 더블클릭',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.3),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  // 이전 슬라이드 영역
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          controller.previousSlide();
                                        },
                                        splashColor: Colors.grey.withOpacity(0.3),
                                        highlightColor: Colors.grey.withOpacity(0.1),
                                        child: const Center(
                                          child: Icon(
                                            Icons.arrow_back_ios,
                                            color: Colors.white30,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 구분선
                                  Container(
                                    width: 1,
                                    color: Colors.white10,
                                  ),
                                  // 다음 슬라이드 영역
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          controller.nextSlide();
                                        },
                                        splashColor: Colors.grey.withOpacity(0.3),
                                        highlightColor: Colors.grey.withOpacity(0.1),
                                        child: const Center(
                                          child: Icon(
                                            Icons.arrow_forward_ios,
                                            color: Colors.white30,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 하단 컨트롤 바
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 프레젠테이션 모드 토글
              Obx(() => IconButton(
                    icon: Icon(
                      Icons.play_arrow,
                      color: controller.isPresentationMode ? Colors.green : Colors.white,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      controller.togglePresentationMode();
                    },
                    tooltip: '프레젠테이션 모드',
                  )),
              // 레이저 포인터 모드 토글
              Obx(() => IconButton(
                    icon: Icon(
                      Icons.highlight,
                      color: controller.isLaserMode ? Colors.red : Colors.white,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      controller.toggleLaserMode();
                    },
                    tooltip: '레이저 포인터',
                  )),
              // 블랙 스크린 토글
              IconButton(
                icon: const Icon(Icons.brightness_1, color: Colors.white),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  controller.toggleBlackScreen();
                },
                tooltip: '블랙 스크린',
              ),
              // 화이트 스크린 토글
              IconButton(
                icon: const Icon(Icons.brightness_7, color: Colors.white),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  controller.toggleWhiteScreen();
                },
                tooltip: '화이트 스크린',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
