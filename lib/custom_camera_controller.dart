import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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
    this.cameraResolution = ResolutionPreset.medium,
  }) {
    assert(
      compressionQuality > 0 && compressionQuality <= 1,
      "compressionQuality value must be bettwen 0 (exclusive) and 1 (inclusive)",
    );
    this.compressionQuality = (compressionQuality * 100).toInt();
    this.isMultipleSelection.value = isMultipleSelection;
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

  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  File? videoFile;
  final duration = ValueNotifier(Duration.zero);

  final imagesCarouselController = ScrollController();

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

    super.dispose();
  }

  void updatedLifecycle(AppLifecycleState state) {
    final CameraController? cameraController = controller.value;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
        cameraController.dispose();
        break;
      case AppLifecycleState.paused:
        if (cameraController.value.isRecordingVideo) {
          pauseVideoRecording();
        }
        break;

      case AppLifecycleState.resumed:
        if (cameraController.value.isRecordingPaused) {
          resumeVideoRecording();
        }
        onNewCameraSelected(cameraController.description);
        break;

      default:
        break;
    }
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    final CameraController? oldController = controller.value;
    controller.value = null;
    await oldController?.dispose();

    final cameraController = CameraController(
      cameraDescription,
      cameraResolution,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

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

  Future<void> init() async {
    cameras.value = await availableCameras();

    await setNewCamera();

    if (await _requestPermissions()) {
      _loadImages();
    }

    imagesCarouselController.addListener(() {
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

  Future<void> setNewCamera([int camIndex = 0]) async {
    final oldController = controller.value;

    if (oldController != null) {
      controller.value = null;
      //Releases the previous camera driver
      await oldController.dispose();
    }

    final tmp = CameraController(
      cameras.value[camIndex],
      cameraResolution,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await tmp.initialize();
    controller.value = tmp;
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
    if (kIsWeb) {
      return true;
    } else if (Platform.isIOS) {
      final status = await Permission.storage.request();
      final status2 = await Permission.photos.request();
      final status3 = await Permission.mediaLibrary.request();
      return status.isGranted && status2.isGranted && status3.isGranted;
    } else if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return false;
  }

  Future<void> takePicture() async {
    if (controller.value == null) return;

    XFile xfile = await controller.value!.takePicture();
    File file = File(xfile.path);
    if (!kIsWeb) {
      await compressImages([file]);
      file = results[file.path] ?? file;

      Uint8List dataFile = await file.readAsBytes();
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();

      await ImageGallerySaver.saveImage(
        dataFile,
        quality: 100,
        name: "$fileName.jpg",
        isReturnImagePathOfIOS: true,
      );
    }
    _loadImages();
  }

  void switchCamera() {
    if (camIndex + 1 >= cameras.value.length) {
      camIndex = 0;
    } else {
      camIndex++;
    }

    setNewCamera(camIndex);
  }

  void toggleFlash() {
    isFlashOn.value = !isFlashOn.value;

    if (controller.value == null) return;

    if (isFlashOn.value) {
      controller.value!.setFlashMode(FlashMode.torch);
    } else {
      controller.value!.setFlashMode(FlashMode.off);
    }
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
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<void> stopVideoRecording() async {
    final result = await _stopVideoRecording();

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
}
