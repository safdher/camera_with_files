import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_gallery/photo_gallery.dart';
import 'package:video_player/video_player.dart';

class InheritedCameraController extends InheritedWidget {
  const InheritedCameraController(
      {super.key, required super.child, required this.data});

  final CustomCameraController data;

  static CustomCameraController of(BuildContext context) {
    final camWithFiles =
        context.dependOnInheritedWidgetOfExactType<InheritedCameraController>();

    if (camWithFiles == null) {
      throw ("Couldn't find a CameraWithFiles on the Widgets Tree");
    }

    return camWithFiles.data;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class CustomCameraController extends ChangeNotifier {
  CustomCameraController({
    bool isMultipleSelection = false,
    double compressionQuality = 1,
    this.cameraResolution = ResolutionPreset.max,
    this.isFullScreen = false,
  }) {
    assert(
      compressionQuality > 0 && compressionQuality <= 1,
      "compressionQuality value must be bettwen 0 (exclusive) and 1 (inclusive)",
    );
    this.compressionQuality = (compressionQuality * 100).toInt();
    this.isMultipleSelection.value = isMultipleSelection;

    _init();
  }

  final isMultipleSelection = ValueNotifier(false);
  late final int compressionQuality;

  var selectedIndexes = ValueNotifier<List<int>>([]);

  var imageMedium = ValueNotifier<Set<Medium>>({});

  final controller = ValueNotifier<CameraController?>(null);
  final isFlashOn = ValueNotifier(false);

  var isExpandedPicturesPanel = ValueNotifier(false);
  var count = ValueNotifier<int>(0);

  final cameras = ValueNotifier<List<CameraDescription>>([]);
  List<Album> imageAlbums = [];
  //Contains all the images, already compressed.
  final results = <String, File>{};
  int camIndex = 0;
  int pageIndex = 1;
  int pageCount = 10;
  final ResolutionPreset cameraResolution;

  final imagesCarouselController = ScrollController();

  final bool isFullScreen;

  //Video related
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  File? videoFile;

  //Video Duration Related
  //Trigger the UI update
  final timeInSeconds = ValueNotifier<int?>(null);
  int currentTimeInMilliseconds = 0;
  static const timerIntervalInMilliseconds = 17;
  bool cancelTimer = false;
  Timer? timer;

  //Storage related
  late String documentsDirectoryPath;

  //Permission related
  bool isAskingPermission = false;

  Future<void> _init() async {
    if (!await _requestPermissions()) return;

    cameras.value = await availableCameras();

    _loadImages();

    await updateSelectedCamera();

    imagesCarouselController.addListener(() {
      if (!imagesCarouselController.hasClients) return;

      if (imagesCarouselController.position.atEdge) {
        bool isTop = imagesCarouselController.position.pixels == 0;
        if (!isTop) {
          if (imageMedium.value.length > (pageCount * pageIndex)) {
            pageIndex++;

            if (pageCount * (pageIndex) > imageMedium.value.length) {
              count.value = imageMedium.value.length;
            } else {
              count.value = pageCount * pageIndex;
            }
          }
        }
      }
    });

    getApplicationDocumentsDirectory()
        .then((value) => documentsDirectoryPath = value.path);
  }

  @override
  void dispose() {
    isMultipleSelection.dispose();
    selectedIndexes.dispose();
    imageMedium.dispose();
    if (controller.hasListeners) {
      controller.dispose();
    }
    isFlashOn.dispose();
    isExpandedPicturesPanel.dispose();
    count.dispose();
    cameras.dispose();

    videoController?.dispose();

    imagesCarouselController.dispose();

    //Duration Timer related
    timeInSeconds.dispose();
    timer?.cancel();

    super.dispose();
  }

  bool get isTakingPicture => controller.value?.value.isTakingPicture == true;

  void updatedLifecycle(AppLifecycleState state) async {
    final CameraController? oldController = controller.value;

    // App state changed before we got the chance to initialize.
    if (oldController != null && !oldController.value.isInitialized) {
      return;
    }

    if (isAskingPermission) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        controller.value = null;
        await oldController?.dispose();
        break;

      case AppLifecycleState.resumed:
        updateSelectedCamera(cameraDescription: oldController?.description);
        break;

      default:
        break;
    }
  }

  Future<void> updateSelectedCamera(
      {CameraDescription? cameraDescription}) async {
    final CameraController? oldController = controller.value;
    controller.value = null;
    await oldController?.dispose();

    late final CameraController cameraController;

    if (cameraDescription != null) {
      cameraController = CameraController(
        cameraDescription,
        cameraResolution,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
    } else {
      cameraController = CameraController(
        cameras.value[camIndex],
        imageFormatGroup: ImageFormatGroup.jpeg,
        cameraResolution,
      );
    }

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (cameraController.value.hasError) {
        showInSnackBar(
            'Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
      controller.value = cameraController;
      //TODO: This should be a function to update all the data like focus, resolution and so on.
      isFlashOn.value = controller.value!.value.flashMode != FlashMode.off;
      //
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
          break;
        case 'cameraPermission':
          // Android & web only
          showInSnackBar('Unknown permission error.');
          break;
        default:
          _showCameraException(e);
          break;
      }
    }
  }

  void showInSnackBar(String message) {
    debugPrint("========\n$message");
  }

  void _loadImages() async {
    if (kIsWeb) {
      return;
    }
    imageAlbums = await PhotoGallery.listAlbums(
      mediumType: MediumType.image,
    );

    for (var element in imageAlbums) {
      var data = await element.listMedia();
      imageMedium.value.addAll(data.items);
    }

    if (pageCount * (pageIndex) > imageMedium.value.length) {
      count.value = imageMedium.value.length;
    } else {
      count.value = pageCount * (pageIndex);
    }
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return false;
    isAskingPermission = true;

    try {
      final p = await Permission.storage.request();
      final p2 = await Permission.photos.request();
      final p3 = await Permission.mediaLibrary.request();
      final p4 = await Permission.camera.request();
      final p5 = await Permission.microphone.request();
      final p6 = await Permission.speech.request();

      isAskingPermission = false;

      return p.isGranted &&
          p2.isGranted &&
          p3.isGranted &&
          p4.isGranted &&
          p5.isGranted &&
          p6.isGranted;
    } catch (e) {
      debugPrint("Error asking permission");
      debugPrint(e.toString());
    }

    return false;
  }

  Future<void> takePicture(double deviceAspectRatio) async {
    if (controller.value == null || controller.value!.value.isTakingPicture) {
      return;
    }

    XFile xfile = await controller.value!.takePicture();

    if (!kIsWeb) {
      final c = await _processImage(xfile, deviceAspectRatio);

      if (c == null) {
        //TODO: show error message here.
        return;
      }

      String fileName = DateTime.now().millisecondsSinceEpoch.toString();

      await ImageGallerySaver.saveImage(
        await c.readAsBytes(),
        quality: 100,
        name: "$fileName.jpg",
        isReturnImagePathOfIOS: true,
      );
      results.putIfAbsent(c.path, () => File(c.path));

      _loadImages();
    }
  }

  /// This process is required to store full screen images and to avoid the
  /// rotated picture error on store new image.
  Future<File?> _processImage(XFile xfile, double deviceAspectRatio) async {
    File file = File(xfile.path);

    img.Image? processedImage;

    if (isFullScreen) {
      var originalImg = img.decodeJpg(await file.readAsBytes());

      if (originalImg == null) return null;

      final originalImgAspectRatio = originalImg.width / originalImg.height;

      if (originalImgAspectRatio > deviceAspectRatio) {
        //Imagem capturada é mais larga que o viewport.
        //Manter altura e cortar largura
        final newWidthScale =
            (deviceAspectRatio * originalImg.height) / originalImg.width;

        final newWidth = originalImg.width * newWidthScale;

        final cropSize = originalImg.width - newWidth;

        processedImage = img.copyCrop(
          originalImg,
          cropSize ~/ 2,
          0,
          newWidth.toInt(),
          originalImg.height,
        );
      } else {
        //Imagem capturada é mais comprida que o viewport.
        //Manter largura e cortar altura
        final newHeightScale =
            (originalImg.width / deviceAspectRatio) / originalImg.height;

        final newHeight = originalImg.height * newHeightScale;

        final cropSize = originalImg.height - newHeight;

        processedImage = img.copyCrop(
          originalImg,
          0,
          cropSize ~/ 2,
          originalImg.width,
          newHeight.toInt(),
        );
      }
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final r = File('$documentsDirectoryPath/$fileName.jpg')
        ..create()
        ..writeAsBytesSync(img.encodeJpg(processedImage));
      file = results[file.path] ?? r;
      return r;
    } else {
      final processedImage = img.decodeJpg(file.readAsBytesSync().toList());

      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final r = File('$documentsDirectoryPath/$fileName.jpg')
        ..create()
        ..writeAsBytesSync(
          img.encodeJpg(processedImage!),
        );
      file = results[file.path] ?? r;

      return r;
    }
  }

  void switchCamera() {
    if (camIndex + 1 >= cameras.value.length) {
      camIndex = 0;
    } else {
      camIndex++;
    }

    updateSelectedCamera();
  }

  void toggleFlash() {
    if (isFlashOn.value) {
      controller.value!.setFlashMode(FlashMode.off);
    } else {
      controller.value!.setFlashMode(FlashMode.always);
    }

    isFlashOn.value = controller.value!.value.flashMode != FlashMode.off;
  }

  void pickFiles() async {
    final ImagePicker picker = ImagePicker();
    if (isMultipleSelection.value) {
      final List<XFile>? images = await picker.pickMultiImage();
      if (images == null) {
        return;
      }
      List<File> files = [];
      for (var element in images) {
        files.add(File(element.path));
      }
      compressImages(files);
    } else {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        return;
      }
      File file = File(image.path);
      compressImages([file]);
    }
  }

  void addToSelection(int index) async {
    if (!isMultipleSelection.value && selectedIndexes.value.isNotEmpty) {
      return;
    }

    if (selectedIndexes.value.contains(index)) {
      selectedIndexes.value.remove(index);
    } else {
      selectedIndexes.value.add(index);
    }

    selectedIndexes.notifyListeners();
  }

  Future<void> compressImages(List<File> files) async {
    for (File file in files) {
      if (results.containsKey(file.path)) {
        continue;
      }

      var decodedImage = await decodeImageFromList(file.readAsBytesSync());

      var result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minHeight: decodedImage.height,
        minWidth: decodedImage.width,
        quality: compressionQuality,
        //This is necessary for avoiding exif images being shown horizontally.
        autoCorrectionAngle: true,
        keepExif: false,
        rotate: 0,
        format: CompressFormat.jpeg,
      );
      Uint8List? blobBytes = result;

      var dir = await getTemporaryDirectory();
      String trimmed = dir.absolute.path;
      String dateTimeString =
          dateTimeToString(DateTime.now(), "dd-yyyy-MMM HH:mm:ss a");
      String pathString = "$trimmed/$dateTimeString.jpeg";
      File newFile = File(pathString);
      newFile.writeAsBytesSync(List.from(blobBytes!));

      results.putIfAbsent(file.path, () => newFile);
    }
  }

  static String dateTimeToString(DateTime dateTime, String pattern) {
    final format = DateFormat(pattern);
    return format.format(dateTime);
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isInitialized) {
      debugPrint('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController.startVideoRecording();
      _startDurationTimer();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<void> stopVideoRecording() async {
    final result = await _stopVideoRecording();
    _stopDurationTimer();

    if (result != null) {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();

      final r = await ImageGallerySaver.saveFile(result.path, name: fileName);

      if (r["isSuccess"] as bool) {
        videoFile = File(r["filePath"]);
        debugPrint("Video saved!");
      } else {
        debugPrint(r["errorMessage"]);
      }
    }
  }

  Future<XFile?> _stopVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      return cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  void _showCameraException(CameraException e) {
    debugPrint(e.code);
    debugPrint(e.description);
  }

  /// Returns the String representation of the video duration.
  String get time {
    if (timeInSeconds.value == null) return "";

    final int minutes = (timeInSeconds.value! ~/ 60);
    final int seconds = (timeInSeconds.value! - 60 * minutes);

    String result = minutes.toString().padLeft(2, "0");
    result += ":";
    result += seconds.toString().padLeft(2, "0");
    return result;
  }

  void _startDurationTimer() {
    if (timer != null) return;

    timer = Timer.periodic(
        const Duration(milliseconds: timerIntervalInMilliseconds), (t) {
      if (cancelTimer) {
        t.cancel();
        timer = null;
      } else {
        currentTimeInMilliseconds += timerIntervalInMilliseconds;
        final currentTimeInSeconds = currentTimeInMilliseconds ~/ 1000;

        if (timeInSeconds.value == null ||
            currentTimeInSeconds > timeInSeconds.value!) {
          timeInSeconds.value = currentTimeInSeconds;
        }
      }
    });
  }

  void _stopDurationTimer() {
    cancelTimer = true;
    timer?.cancel();
    timer = null;
    timeInSeconds.value = null;
  }
}
