import 'dart:io';
import 'package:camera_with_files/camera_with_files.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<File> files = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (files.isNotEmpty)
                ...files.map<Image>((ele) {
                  if (kIsWeb) {
                    return Image.network(ele.path);
                  }
                  return Image.file(ele);
                }).toList(),
              TextButton(
                onPressed: () async {
                  var data = await Navigator.of(context).push(
                    MaterialPageRoute<List<File>>(
                      builder: (BuildContext context) => const CameraApp(
                          isMultiple: true,
                          isSimpleUI: true,
                          compressedSize: 100000),
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
