import 'dart:io';
import 'package:camera_with_files/camera_with_files.dart';
import 'package:example/video_player.dart';
import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
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

                  return Image.file(e);
                }).toList(),
              TextButton(
                onPressed: () async {
                  files.clear();
                  var data = await Navigator.of(context).push(
                    MaterialPageRoute<List<File>>(
                      builder: (_) => const CameraApp(
                        compressionQuality: .5,
                        isMultipleSelection: false,
                        // showGallery: false,
                        // showOpenGalleryButton: false,
                      ),
                    ),
                  );

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
