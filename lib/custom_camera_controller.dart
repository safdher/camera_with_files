import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:media_scanner/media_scanner.dart';
import 'package:path/path.dart';
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
    this.storeOnGallery = false,
    this.directoryName,
  }) {
    assert(
      compressionQuality > 0 && compressionQuality <= 1,
      "compressionQuality value must be bettwen 0 (exclusive) and 1 (inclusive)",
    );
    if (storeOnGallery) {
      assert(
        directoryName != null,
        "To store the file in a public folder you have pass a  directory name",
      );
    }

    this.compressionQuality = (compressionQuality * 100).toInt();
    this.isMultipleSelection.value = isMultipleSelection;

    _init();
  }

  //TODO: Allow multiple selection
  final isMultipleSelection = ValueNotifier(false);

  // Related to Gallery media listing
  var selectedIndexes = ValueNotifier<List<int>>([]);
  var imageMedium = ValueNotifier<Set<Medium>>({});
  var isExpandedPicturesPanel = ValueNotifier(false);
  var count = ValueNotifier<int>(0);
  List<Album> imageAlbums = [];
  int pageIndex = 1;
  int pageCount = 10;
  final imagesCarouselController = ScrollController();

  // Camera related
  final controller = ValueNotifier<CameraController?>(null);
  final isFlashOn = ValueNotifier(false);
  late final int compressionQuality;
  final cameras = ValueNotifier<List<CameraDescription>>([]);
  static int currentCameraIndex = 0;
  final ResolutionPreset cameraResolution;
  File? image;
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

  // Storage related
  /// The directory name to be used for storing the files if [storeOnGallery] is true.
  ///
  String? directoryName;
  Directory? rootDirectory;

  // Permission related
  bool storeOnGallery = false;
  bool isAskingPermission = false;
  bool hasMicrophonePermission = false;
  final hasCameraPermission = ValueNotifier(false);
  // Required for storing media on the documents folder
  bool hasStoragePermission = false;
  bool hasIOSPhotosPermission = false;

  Future<void> _init() async {
    if (!await _requestPermissions()) return;

    cameras.value = await availableCameras();

    _loadImages();

    await updateSelectedCamera();

    rootDirectory = await _filesDirectory;

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
  }

  @override
  void dispose() {
    isMultipleSelection.dispose();
    selectedIndexes.dispose();
    imageMedium.dispose();

    controller.dispose();

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
    if (oldController != null && !oldController.value.isInitialized ||
        !hasCameraPermission.value) {
      return;
    }

    if (isAskingPermission) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (_isRecordingVideo) {
          await stopVideoRecording();
        }
        break;

      case AppLifecycleState.resumed:
        updateSelectedCamera(cameraDescription: oldController?.description);
        break;

      default:
        break;
    }
  }

  bool get _isRecordingVideo {
    if (controller.value == null) return false;

    return controller.value!.value.isRecordingVideo;
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
        enableAudio: hasMicrophonePermission,
      );
    } else {
      cameraController = CameraController(
        cameras.value[currentCameraIndex],
        imageFormatGroup: ImageFormatGroup.jpeg,
        cameraResolution,
        enableAudio: hasMicrophonePermission,
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

  // TODO: Extract to Usecase
  void _loadImages() async {
    if (kIsWeb || !hasStoragePermission) {
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
      hasStoragePermission = await _requestPermission(Permission.storage);

      hasCameraPermission.value = await _requestPermission(Permission.camera);

      hasMicrophonePermission = await _requestPermission(Permission.microphone);

      if (Platform.isIOS) {
        hasIOSPhotosPermission = await _requestPermission(Permission.photos);
      }

      return hasCameraPermission.value;
    } catch (e) {
      debugPrint("Error asking permission");
      debugPrint(e.toString());
    }

    isAskingPermission = true;
    return false;
  }

  Future<bool> _requestPermission(Permission p) async {
    if (await p.isGranted) return true;

    return (await p.request()).isGranted;
  }

  Future<void> takePicture(double deviceAspectRatio) async {
    if (controller.value == null || controller.value!.value.isTakingPicture) {
      return;
    }

    XFile xfile = await controller.value!.takePicture();

    if (kIsWeb) return;

    image = await _processImage(File(xfile.path), deviceAspectRatio);

    if (image != null) {
      _saveOnGallery(image!, isPicture: true);
    }
  }

  /// This process is required to for cropping full screen pictures.
  // TODO: Extract to Usecase
  Future<File?> _processImage(
    File originalFile,
    double deviceAspectRatio,
  ) async {
    img.Image? processedImage;
    var originalImg = img.decodeJpg(await originalFile.readAsBytes());

    if (originalImg == null) return null;

    //The alternative solution here is to mirror the preview.
    if (cameras.value[currentCameraIndex].lensDirection ==
            CameraLensDirection.front &&
        Platform.isAndroid) {
      originalImg = img.flipHorizontal(originalImg);
    }

    if (isFullScreen) {
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
    } else {
      processedImage = originalImg;
    }
    final paths = split(originalFile.path);
    final fileExtension = extension(originalFile.path, 1);
    paths.removeRange(paths.length - 2, paths.length);
    String currentTime = DateTime.now().millisecondsSinceEpoch.toString();
    final finalPath = joinAll([...paths, currentTime]) + fileExtension;
    return File(finalPath)
      ..create()
      ..writeAsBytesSync(
        img.encodeJpg(processedImage),
      );
  }

  // TODO: Extract to Usecase
  Future<File?> _saveOnGallery(File file, {bool isPicture = false}) async {
    if (!hasStoragePermission || !storeOnGallery || directoryName == null) {
      return null;
    }

    try {
      File? finalFile;
      if (Platform.isAndroid) {
        late ScannerResultModel result;
        try {
          if (isPicture) {
            result = await MediaScanner.saveImage(file.readAsBytesSync());
          } else {
            result = await MediaScanner.saveFile(file.path);
          }

          if (result.isSuccess && result.filePath != null) {
            finalFile = File(result.filePath!);
          } else {
            throw Exception(result.errorMessage);
          }
        } catch (e) {
          _showCameraException(e, "MediaScannerExcetion");
        }
      } else {
        rootDirectory = rootDirectory ?? await _filesDirectory;
        //TODO: If needed, scan the new media for IOs too.
        finalFile = File("$rootDirectory")
          ..writeAsBytes(file.readAsBytesSync());
      }

      return finalFile;
    } catch (e) {
      _showCameraException(e, "MediaScannerExcetion");
    }
    return null;
  }

  Future<Directory?> get _filesDirectory async {
    if (Platform.isAndroid && hasStoragePermission) {
      return await getExternalStorageDirectory();
    } else {
      if (hasIOSPhotosPermission) {
        return await getApplicationDocumentsDirectory();
      }
    }
    return null;
  }

  void switchCamera() {
    if (currentCameraIndex + 1 >= cameras.value.length) {
      currentCameraIndex = 0;
    } else {
      currentCameraIndex++;
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
    _cancelDurationTimer();
    if (result != null) {
      final file = File(result.path);
      videoFile = file;
      await _saveOnGallery(file);
    }
  }

  Future<XFile?> _stopVideoRecording() async {
    final CameraController? cameraController = controller.value;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      return await cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e, "ERROR WHEN STOPPING THE VIDEO");
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

  void _showCameraException(dynamic e, [String? tag]) {
    if (tag != null) {
      debugPrint(tag);
    }

    //TODO: add other cases of exceptions
    switch (e.runtimeType) {
      case CameraException:
        debugPrint((e as CameraException).code);
        debugPrint(e.description);
        break;
      default:
    }
  }

  // TODO: Extract to Usecase
  /// Returns the String representation of the video duration.
  String get videoDuration {
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

  void _cancelDurationTimer() {
    cancelTimer = true;
    timer?.cancel();
    timer = null;
    timeInSeconds.value = null;
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
}
