import 'dart:io';

import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:flutter/material.dart';

class VideoPlayer extends StatefulWidget {
  VideoPlayer({Key? key, required this.videoFile})
      : super(
          //This way the video player doesn't cache any recorded video files played before.
          key: key ?? ValueKey(videoFile.path),
        );

  final File videoFile;

  @override
  VideoPlayerState createState() => VideoPlayerState();
}

class VideoPlayerState extends State<VideoPlayer> {
  late vp.VideoPlayerController _controller;
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = vp.VideoPlayerController.file(
      widget.videoFile,
    )..initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
        setState(() {});
      });

    _controller.addListener(() {
      bool oldState = isPlaying;
      isPlaying = _controller.value.isPlaying;
      if (isPlaying != oldState) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: vp.VideoPlayer(_controller),
              ),
            )
          : const SizedBox.shrink(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          isPlaying ? _controller.pause() : _controller.play();
        },
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }
}

bool isImage(String path) {
  final mimeType = lookupMimeType(path);

  return mimeType?.startsWith('image/') ?? false;
}

bool isVideo(String path) {
  final mimeType = lookupMimeType(path);

  return mimeType?.startsWith('video/') ?? false;
}
