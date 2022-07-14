library camera_with_files;

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:camera_with_files/custom_camera_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_gallery/photo_gallery.dart';

class CameraApp extends StatefulWidget {
  const CameraApp({
    super.key,
    this.compressionQuality = 1,
    this.isMultipleSelection = true,
    this.cameraResolution = ResolutionPreset.medium,
    this.showGallery = true,
    this.showOpenGalleryButton = true,
  }) : assert(
          compressionQuality > 0 && compressionQuality <= 1,
          "compressionQuality value must be bettwen 0 (exclusive) and 1 (inclusive)",
        );

  final bool isMultipleSelection;
  final double compressionQuality;
  final ResolutionPreset cameraResolution;
  final bool showGallery;
  final bool showOpenGalleryButton;

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> with WidgetsBindingObserver {
  late CustomCameraController controller;

  @override
  void initState() {
    super.initState();
    controller = CustomCameraController(
      compressionQuality: widget.compressionQuality,
      isMultipleSelection: widget.isMultipleSelection,
      cameraResolution: widget.cameraResolution,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.init();
    if (widget.showGallery) {
      precacheImage(
        const AssetImage(
          "assets/placeholder.png",
          package: "camera_with_files",
        ),
        context,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.updatedLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return InheritedCameraController(
      data: controller,
      child: Builder(
        builder: (context) {
          controller = InheritedCameraController.of(context);
          return WillPopScope(
            onWillPop: () async {
              debugPrint("Show a dialog");
              return Future.value(true);
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  Center(
                    child: ValueListenableBuilder<CameraController?>(
                        valueListenable: controller.controller,
                        builder: (context, val, _) {
                          if (val == null || !val.value.isInitialized) {
                            return const SizedBox.shrink();
                          }
                          final size = MediaQuery.of(context).size;
                          return SizedBox.fromSize(
                            size: size,
                            child: CameraPreview(val),
                          );
                        }),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: BottomPanel(
                      showGallery: widget.showGallery,
                      showOpenGalleryButton: widget.showOpenGalleryButton,
                    ),
                  ),
                  SafeArea(
                    child: Align(
                        alignment: Alignment.topCenter,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: Navigator.of(context).pop,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              onPressed: controller.toggleFlash,
                              icon: ValueListenableBuilder<bool>(
                                valueListenable: controller.isFlashOn,
                                builder: (_, val, child) {
                                  if (val) {
                                    return const Icon(
                                      Icons.flash_on,
                                      size: 30,
                                      color: Colors.white,
                                    );
                                  }
                                  return child!;
                                },
                                child: const Icon(
                                  Icons.flash_off,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ExpandPicturesPanelButton extends StatelessWidget {
  const ExpandPicturesPanelButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return GestureDetector(
      onTap: () async {
        controller.isExpandedPicturesPanel.value = true;
      },
      child: Container(
        color: Colors.transparent,
        height: 48,
        width: MediaQuery.of(context).size.width,
        child: const Icon(
          Icons.arrow_drop_up_outlined,
          color: Colors.white,
        ),
      ),
    );
  }
}

class BottomPanel extends StatelessWidget {
  const BottomPanel({
    Key? key,
    required this.showGallery,
    required this.showOpenGalleryButton,
  }) : super(key: key);

  final bool showGallery;
  final bool showOpenGalleryButton;

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return Container(
      width: MediaQuery.of(context).size.width,
      color: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          //Photographs gallery
          if (showGallery)
            SizedBox(
              height: 130,
              child: Stack(
                children: [
                  Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: controller.isExpandedPicturesPanel,
                        builder: (context, isExpanded, child) {
                          if (isExpanded && !Platform.isIOS) {
                            return const SizedBox(height: 48);
                          }
                          return child!;
                        },
                        child: const ExpandPicturesPanelButton(),
                      ),
                      if (!kIsWeb) const ImagesCarousel(),
                    ],
                  ),
                  const Positioned(
                    top: 20,
                    right: 0,
                    child: BadgeButton(),
                  ),
                ],
              ),
            ),

          //Buttons panel
          SizedBox(
            height: 80,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: (!kIsWeb && showOpenGalleryButton)
                        ? SizedBox(
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: controller.pickFiles,
                                icon: const Icon(
                                  Icons.image,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const Expanded(child: ActionButton()),
                  Expanded(
                    child: ValueListenableBuilder<List<CameraDescription>>(
                      valueListenable: controller.cameras,
                      builder: (_, value, child) {
                        if (kIsWeb || value.length < 2) {
                          return const SizedBox.shrink();
                        }

                        return child!;
                      },
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: controller.switchCamera,
                          icon: const Icon(
                            Icons.cameraswitch,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              "Hold for video, tap for photo",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionButton extends StatefulWidget {
  const ActionButton({Key? key}) : super(key: key);

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<Decoration> decorationAnimation;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 60),
    );

    decorationAnimation = DecorationTween(
      begin: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Colors.red, Colors.transparent],
          stops: [0, 0],
        ),
        border: Border.all(color: Colors.white, width: 3),
      ),
      end: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Colors.red, Colors.transparent],
          stops: [1, 1],
        ),
        border: Border.all(color: Colors.white, width: 3),
      ),
    ).animate(animationController);
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  void _stopVideo(CustomCameraController controller) async {
    animationController.reverse(from: 1);
    await controller.stopVideoRecording();

    if (controller.videoFile != null && mounted) {
      Navigator.of(context).pop([controller.videoFile as File]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return GestureDetector(
      onTap: () async {
        animationController.duration = const Duration(milliseconds: 300);
        animationController.forward();
        await controller.takePicture();

        if (mounted) {
          final files = controller.results.values.map((e) => e).toList();
          Navigator.of(context).pop(files);
        }
      },
      onLongPress: () async {
        animationController.duration = const Duration(milliseconds: 600);
        animationController.forward(from: 0);
        await controller.startVideoRecording();
      },
      onLongPressEnd: (_) => _stopVideo(controller),
      onLongPressCancel: () => _stopVideo(controller),
      child: SizedBox.square(
        dimension: 60,
        child: DecoratedBoxTransition(
          decoration: decorationAnimation,
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class BadgeButton extends StatelessWidget {
  const BadgeButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);

    return ValueListenableBuilder<List<int>>(
        valueListenable: controller.selectedIndexes,
        builder: (_, val, child) {
          if (val.isEmpty) {
            return const SizedBox.shrink();
          }
          return GestureDetector(
            onTap: () {
              debugPrint(" ");
            },
            child: SizedBox.square(
              dimension: 48,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.check, color: Colors.white),
                    Align(
                      alignment: const Alignment(.5, .6),
                      child: Text(
                        val.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }
}

class ImagesCarousel extends StatelessWidget {
  const ImagesCarousel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = InheritedCameraController.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: controller.imagesCarouselController,
      child: ValueListenableBuilder<int>(
          valueListenable: controller.count,
          builder: (context, value, child) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(value, (index) {
                return GestureDetector(
                  onLongPress: () => controller.addToSelection(index),
                  onTap: () async {
                    if (controller.selectedIndexes.value.isEmpty) {
                      controller.addToSelection(index);
                      debugPrint("showImagesPreview");
                    } else {
                      controller.addToSelection(index);
                    }
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(left: 2),
                        child: FadeInImage(
                          fit: BoxFit.cover,
                          placeholder: const AssetImage(
                            "assets/placeholder.png",
                            package: "camera_with_files",
                          ),
                          image: ThumbnailProvider(
                            mediumId: controller.imageMedium.value
                                .elementAt(index)
                                .id,
                            mediumType: MediumType.image,
                            width: 128,
                            height: 128,
                            highQuality: false,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<List<int>>(
                        valueListenable: controller.selectedIndexes,
                        builder: (_, value, child) {
                          if (value.contains(index)) {
                            return child!;
                          }

                          return const SizedBox.shrink();
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(left: 2),
                          color: Colors.grey.withOpacity(0.4),
                          child: const Center(
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }),
    );
  }
}
