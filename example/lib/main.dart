import 'dart:io';
import 'package:camera_with_files/camera_with_files.dart';
import 'package:example/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> files = [];

  @override
  void initState() {
    super.initState();
    restoreUIBars();
  }

  void restoreUIBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (files.isNotEmpty)
                ...files.map<Widget>((e) {
                  if (isVideo(e.path)) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width,
                        maxHeight: size.height,
                      ),
                      child: VideoPlayer(videoFile: e, key: ValueKey(e.path)),
                    );
                  }

                  return SizedBox.fromSize(
                    size: size,
                    child: Image.file(e, fit: BoxFit.cover),
                  );
                }).toList(),
              TextButton(
                onPressed: () async {
                  files.clear();
                  var data = await Navigator.of(context).push(
                    MaterialPageRoute<List<File>>(
                      builder: (_) => const CameraApp(
                        compressionQuality: 1.0,
                        isMultipleSelection: false,
                        showGallery: false,
                        showOpenGalleryButton: false,
                      ),
                    ),
                  );
                  restoreUIBars();

                  if (data != null) {
                    setState(() {
                      files = data;
                    });
                  }
                },
                child: const Text("Click"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
