import 'package:flutter/material.dart';
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
          // 자이로 모드 토글 버튼
          Obx(() => IconButton(
                icon: Icon(
                  Icons.screen_rotation,
                  color: controller.gyroEnabled.value ? Colors.blue : Colors.white,
                ),
                onPressed: controller.toggleGyroMode,
              )),
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
            // 자이로 모드 감도 조절 슬라이더
            Obx(() => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: controller.gyroEnabled.value
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              const Text(
                                '자이로 감도',
                                style: TextStyle(color: Colors.white70),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.speed, color: Colors.white),
                                  Expanded(
                                    child: Slider(
                                      value: controller.sensitivity.value,
                                      min: 0.5,
                                      max: 5.0,
                                      divisions: 9, // 0.5 단위로 조절 가능
                                      label: controller.sensitivity.value.toStringAsFixed(1),
                                      onChanged: controller.adjustSensitivity,
                                      activeColor: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                )),
            // 메인 제어 영역
            Expanded(
              child: GestureDetector(
                onPanUpdate: (details) {
                  if (!controller.gyroEnabled.value) {
                    controller.updateMousePosition(
                      details.localPosition,
                      screenSize,
                    );
                  }
                },
                onPanStart: (_) => controller.startDrag(),
                onPanEnd: (_) => controller.endDrag(),
                onTapUp: (_) => controller.sendClick('left'),
                onDoubleTapDown: (_) => controller.sendClick('double'),
                onSecondaryTapUp: (_) => controller.sendClick('right'),
                onLongPress: controller.toggleLaserMode,
                onLongPressEnd: (_) => controller.toggleLaserMode(),
                child: Container(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      // 이전 슬라이드 영역
                      Expanded(
                        child: InkWell(
                          onTap: controller.previousSlide,
                          splashColor: Colors.white24,
                          highlightColor: Colors.white10,
                          child: const Center(
                            child: Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white30,
                              size: 40,
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
                        child: InkWell(
                          onTap: controller.nextSlide,
                          splashColor: Colors.white24,
                          highlightColor: Colors.white10,
                          child: const Center(
                            child: Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white30,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ],
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
