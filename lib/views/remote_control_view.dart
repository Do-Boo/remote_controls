import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/remote_control_controller.dart';

class RemoteControlView extends GetView<RemoteControlController> {
  const RemoteControlView({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('리모컨'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: () {
              controller.disconnect();
              Get.back();
            },
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
                  // 레이저 포인터 모드일 때만 마우스 움직임 활성화
                  if (controller.isLaserMode.value) {
                    controller.updateMousePosition(
                      details.localPosition.dx,
                      details.localPosition.dy,
                    );
                  }
                },
                onTapUp: (details) {
                  HapticFeedback.mediumImpact(); // 햅틱 피드백
                  if (controller.isLaserMode.value) {
                    controller.sendClick('left');
                  } else {
                    if (details.localPosition.dx < screenSize.width / 2) {
                      controller.previousSlide();
                    } else {
                      controller.nextSlide();
                    }
                  }
                },
                child: Container(
                  color: Colors.transparent,
                  child: Material(
                    // Material 위젯 추가
                    color: Colors.transparent,
                    child: InkWell(
                      // InkWell로 탭 이펙트 추가
                      onTap: () {}, // 필수 (이펙트만 위한 빈 콜백)
                      splashColor: Colors.grey.withOpacity(0.3),
                      highlightColor: Colors.grey.withOpacity(0.1),
                      child: Obx(() => controller.isLaserMode.value
                          ? const Center(
                              child: Text(
                                '트랙패드 영역',
                                style: TextStyle(
                                  color: Colors.white30,
                                  fontSize: 16,
                                ),
                              ),
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
            // 볼륨 컨트롤
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.white),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withOpacity(0.3),
                      ),
                      child: Slider(
                        value: 0.5,
                        onChanged: (value) => controller.adjustVolume(value - 0.5),
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Obx(() => IconButton(
                  icon: Icon(
                    Icons.play_arrow,
                    color: controller.isPresentationMode.value ? Colors.green : Colors.white,
                  ),
                  onPressed: controller.togglePresentationMode,
                  tooltip: '프레젠테이션 모드',
                )),
            Obx(() => IconButton(
                  icon: Icon(
                    Icons.highlight,
                    color: controller.isLaserMode.value ? Colors.red : Colors.white,
                  ),
                  onPressed: controller.toggleLaserMode,
                  tooltip: '레이저 포인터',
                )),
            IconButton(
              icon: const Icon(Icons.brightness_1, color: Colors.white),
              onPressed: controller.toggleBlackScreen,
              tooltip: '블랙 스크린',
            ),
            IconButton(
              icon: const Icon(Icons.brightness_7, color: Colors.white),
              onPressed: controller.toggleWhiteScreen,
              tooltip: '화이트 스크린',
            ),
          ],
        ),
      ),
    );
  }
}
