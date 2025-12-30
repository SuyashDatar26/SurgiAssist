import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class ImageViewerPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImageViewerPage({
    Key? key,
    required this.imageUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late PageController _pageController;
  late PhotoViewController _photoController;
  late stt.SpeechToText _speech;

  Timer? _startDelayTimer;

  int _currentIndex = 0;

  bool _isListening = false;
  bool _micLocked = false; // 🔒 only true when leaving page

  // ================= INIT =================

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _photoController = PhotoViewController();
    _speech = stt.SpeechToText();

    // 🎙️ Start mic after UI stabilizes
    _startDelayTimer = Timer(
      const Duration(seconds: 2),
      _startMic,
    );
  }

  // ================= MIC =================

  Future<void> _startMic() async {
    if (!mounted || _micLocked || _isListening) return;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return;

    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'notListening' || status == 'done') && !_micLocked) {
          _restartListening();
        }
      },
      onError: (_) {
        if (!_micLocked) {
          _restartListening();
        }
      },
    );

    if (!available) return;

    _listen();
  }

  void _listen() {
    if (_micLocked || _isListening) return;

    debugPrint("🎙️ MIC LISTENING");

    _speech.listen(
      listenFor: const Duration(minutes: 30),
      pauseFor: const Duration(seconds: 8),
      partialResults: false,
      cancelOnError: false,
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase().trim();
        if (text.isNotEmpty) {
          debugPrint("🎤 Heard: $text");
          _handleNlpCommand(text);
        }
      },
    );

    _isListening = true;
  }

  void _restartListening() async {
    if (_micLocked) return;

    _isListening = false;
    await Future.delayed(const Duration(milliseconds: 400));
    _listen();
  }

  void _stopMic() {
    if (_isListening) {
      debugPrint("⏹️ MIC STOPPED");
      _speech.stop();
      _isListening = false;
    }
  }

  // ================= NLP INTENT ENGINE =================

  void _handleNlpCommand(String speech) {
    if (_micLocked) return;

    final text =
    speech.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();

    bool commandExecuted = false;

    if (_containsAny(text, ['next', 'forward', 'next image'])) {
      _nextImage();
      commandExecuted = true;
    } else if (_containsAny(text, ['previous', 'back', 'go back'])) {
      _previousImage();
      commandExecuted = true;
    } else if (_containsAny(text, ['zoom in', 'enlarge', 'magnify'])) {
      _zoomIn();
      commandExecuted = true;
    } else if (_containsAny(text, ['zoom out', 'reduce', 'minimize'])) {
      _zoomOut();
      commandExecuted = true;
    }

    /// 🔁 CRITICAL: restart mic after command execution
    if (commandExecuted) {
      _stopMic();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_micLocked) {
          _startMic();
        }
      });
    }
  }

  bool _containsAny(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  // ================= IMAGE CONTROLS =================

  void _nextImage() {
    if (_currentIndex < widget.imageUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousImage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _zoomIn() {
    _photoController.scale =
        (_photoController.scale ?? 1.0) * 1.25;
  }

  void _zoomOut() {
    _photoController.scale =
        (_photoController.scale ?? 1.0) / 1.25;
  }

  // ================= BACK =================

  Future<bool> _onBackPressed() async {
    _micLocked = true; // 🔒 permanently stop mic
    _stopMic();
    Navigator.pop(context);
    return false;
  }

  // ================= DISPOSE =================

  @override
  void dispose() {
    _micLocked = true;
    _startDelayTimer?.cancel();
    _stopMic();
    _pageController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBackPressed,
          ),
          title: Text(
            'Image ${_currentIndex + 1} / ${widget.imageUrls.length}',
          ),
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: widget.imageUrls.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
              _photoController.scale = 1.0;
            });
          },
          itemBuilder: (context, index) {
            return PhotoView(
              controller: _photoController,
              imageProvider: NetworkImage(widget.imageUrls[index]),
              backgroundDecoration:
              const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            );
          },
        ),
      ),
    );
  }
}
