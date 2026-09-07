import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

class _ImageViewerPageState extends State<ImageViewerPage>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // CONTROLLERS
  // ---------------------------------------------------------------------------

  late PageController _pageController;
  late stt.SpeechToText _speech;

  final FocusNode _keyboardFocusNode = FocusNode();

  late AnimationController _entranceController;
  late AnimationController _hudController;
  late AnimationController _micController;
  late AnimationController _controlsController;
  late AnimationController _imageController;

  // ---------------------------------------------------------------------------
  // PHOTO VIEW CONTROLLERS
  // ---------------------------------------------------------------------------

  final Map<int, PhotoViewController> _photoControllers = {};

  PhotoViewController _controllerFor(int index) {
    return _photoControllers.putIfAbsent(
      index,
          () => PhotoViewController(),
    );
  }

  // ---------------------------------------------------------------------------
  // TIMERS
  // ---------------------------------------------------------------------------

  Timer? _startDelayTimer;
  Timer? _micRestartTimer;
  Timer? _feedbackTimer;
  Timer? _hudHideTimer;

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  int _currentIndex = 0;

  bool _isListening = false;
  bool _micLocked = false;

  bool _isStartingMic = false;

  bool _speechInitialized = false;

  bool _processingVoiceCommand = false;

  bool _showControls = true;
  bool _showFilmstrip = true;
  bool _isChangingPage = false;

  String _voiceFeedback = 'Voice assistant ready';

  double _imageProgress = 0.0;

  // ---------------------------------------------------------------------------
  // VOICE SESSION CONTROL
  // ---------------------------------------------------------------------------
  //
  // speech_to_text can emit callbacks slightly after stop()/done().
  // This generation number allows old callbacks to be ignored.
  //

  int _speechGeneration = 0;

  // ---------------------------------------------------------------------------
  // COLORS
  // ---------------------------------------------------------------------------

  static const Color _background = Color(0xFF02080D);
  static const Color _surface = Color(0xFF07131D);
  static const Color _surfaceLight = Color(0xFF0C202D);

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _teal = Color(0xFF0E7490);
  static const Color _white = Color(0xFFF5FAFC);
  static const Color _secondaryText = Color(0xFFA9C0CC);
  static const Color _mutedText = Color(0xFF6F8A98);

  static const Color _success = Color(0xFF22C55E);
  static const Color _warning = Color(0xFFF59E0B);

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1,
    );

    _pageController = PageController(
      initialPage: _currentIndex,
    );

    _speech = stt.SpeechToText();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _hudController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _micController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _controlsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _imageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _entranceController.forward();
    _hudController.forward();
    _controlsController.forward();
    _imageController.forward();

    _updateProgress();

    // Keep automatic microphone startup.
    _startDelayTimer = Timer(
      const Duration(seconds: 2),
      _startMic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PROGRESS
  // ---------------------------------------------------------------------------

  void _updateProgress() {
    if (widget.imageUrls.isEmpty) {
      _imageProgress = 0;
      return;
    }

    _imageProgress = (_currentIndex + 1) / widget.imageUrls.length;
  }

  // ---------------------------------------------------------------------------
  // MICROPHONE
  // ---------------------------------------------------------------------------

  Future<void> _startMic() async {
    if (!mounted ||
        _micLocked ||
        _isListening ||
        _isStartingMic ||
        _processingVoiceCommand) {
      return;
    }

    _isStartingMic = true;

    final int generationAtStart = _speechGeneration;

    try {
      final permission = await Permission.microphone.request();

      if (!mounted ||
          _micLocked ||
          generationAtStart != _speechGeneration) {
        return;
      }

      if (!permission.isGranted) {
        _setVoiceFeedback('Microphone permission required');
        return;
      }

      // ---------------------------------------------------------------
      // INITIALIZE SPEECH RECOGNITION ONLY ONCE
      // ---------------------------------------------------------------

      if (!_speechInitialized) {
        final available = await _speech.initialize(
          onStatus: _handleSpeechStatus,
          onError: (error) {
            debugPrint(
              '🎙️ Speech error: ${error.errorMsg}',
            );

            if (!mounted || _micLocked) {
              return;
            }

            if (_processingVoiceCommand) {
              return;
            }

            _setListeningState(false);

            _scheduleMicRestart(
              delay: const Duration(
                milliseconds: 650,
              ),
            );
          },
        );

        if (!mounted ||
            _micLocked ||
            generationAtStart != _speechGeneration) {
          return;
        }

        if (!available) {
          _setVoiceFeedback(
            'Voice recognition unavailable',
          );

          return;
        }

        _speechInitialized = true;
      }

      if (!mounted ||
          _micLocked ||
          _isListening ||
          _processingVoiceCommand ||
          generationAtStart != _speechGeneration) {
        return;
      }

      await _listen(
        expectedGeneration: generationAtStart,
      );
    } catch (e, stackTrace) {
      debugPrint(
        '🎙️ Microphone start error: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (mounted &&
          !_micLocked &&
          generationAtStart == _speechGeneration) {
        _setVoiceFeedback(
          'Unable to start voice recognition',
        );

        _setListeningState(false);

        _scheduleMicRestart(
          delay: const Duration(
            milliseconds: 1000,
          ),
        );
      }
    } finally {
      _isStartingMic = false;
    }
  }

  // ---------------------------------------------------------------------------
  // SPEECH STATUS
  // ---------------------------------------------------------------------------

  void _handleSpeechStatus(String status) {
    debugPrint(
      '🎙️ Speech status: $status',
    );

    if (!mounted || _micLocked) {
      return;
    }

    final normalizedStatus = status.toLowerCase().trim();

    if (normalizedStatus == 'listening') {
      if (!_isListening) {
        _setListeningState(true);
      }

      if (!_micController.isAnimating) {
        _micController.repeat(
          reverse: true,
        );
      }

      if (!_processingVoiceCommand) {
        _setVoiceFeedback(
          'Listening for command...',
        );
      }

      return;
    }

    if (normalizedStatus == 'notlistening' ||
        normalizedStatus == 'done') {
      _setListeningState(false);

      _micController.stop();
      _micController.value = 0;

      // speech_to_text ends recognition sessions naturally.
      // Automatically create another listening session.
      if (!_processingVoiceCommand &&
          !_micLocked) {
        _scheduleMicRestart(
          delay: const Duration(
            milliseconds: 350,
          ),
        );
      }

      return;
    }
  }

  // ---------------------------------------------------------------------------
  // LISTEN
  // ---------------------------------------------------------------------------

  Future<void> _listen({
    int? expectedGeneration,
  }) async {
    if (!mounted ||
        _micLocked ||
        _isListening ||
        _processingVoiceCommand) {
      return;
    }

    if (expectedGeneration != null &&
        expectedGeneration != _speechGeneration) {
      return;
    }

    final int listenGeneration = _speechGeneration;

    debugPrint(
      '🎙️ MIC LISTENING',
    );

    try {
      _setListeningState(true);

      _micController.repeat(
        reverse: true,
      );

      _setVoiceFeedback(
        'Listening for command...',
      );

      await _speech.listen(
        listenFor: const Duration(
          minutes: 30,
        ),
        pauseFor: const Duration(
          seconds: 5,
        ),
        partialResults: false,
        cancelOnError: false,
        onResult: (result) {
          if (!mounted ||
              _micLocked ||
              listenGeneration != _speechGeneration) {
            return;
          }

          final text = result.recognizedWords
              .toLowerCase()
              .trim();

          if (text.isEmpty) {
            return;
          }

          debugPrint(
            '🎤 Heard: $text',
          );

          _handleNlpCommand(
            text,
            expectedGeneration: listenGeneration,
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint(
        '🎙️ Speech listen error: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (mounted &&
          !_micLocked &&
          listenGeneration == _speechGeneration) {
        _setListeningState(false);

        _micController.stop();
        _micController.value = 0;

        _scheduleMicRestart(
          delay: const Duration(
            milliseconds: 800,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LISTENING STATE
  // ---------------------------------------------------------------------------

  void _setListeningState(bool listening) {
    if (!mounted) {
      return;
    }

    if (_isListening == listening) {
      if (listening &&
          !_micController.isAnimating) {
        _micController.repeat(
          reverse: true,
        );
      }

      return;
    }

    setState(() {
      _isListening = listening;
    });

    if (listening) {
      if (!_micController.isAnimating) {
        _micController.repeat(
          reverse: true,
        );
      }
    } else {
      _micController.stop();
      _micController.value = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // MIC RESTART
  // ---------------------------------------------------------------------------

  void _scheduleMicRestart({
    Duration delay = const Duration(
      milliseconds: 350,
    ),
  }) {
    if (!mounted ||
        _micLocked ||
        _processingVoiceCommand) {
      return;
    }

    _micRestartTimer?.cancel();

    final int restartGeneration = _speechGeneration;

    _micRestartTimer = Timer(
      delay,
          () async {
        if (!mounted ||
            _micLocked ||
            _processingVoiceCommand ||
            _isStartingMic ||
            _isListening ||
            restartGeneration != _speechGeneration) {
          return;
        }

        await _startMic();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RESTART LISTENING
  // ---------------------------------------------------------------------------

  Future<void> _restartListening({
    Duration delay = const Duration(
      milliseconds: 250,
    ),
  }) async {
    if (!mounted || _micLocked) {
      return;
    }

    _micRestartTimer?.cancel();

    final int restartGeneration = _speechGeneration;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        '🎙️ Speech restart stop error: $e',
      );
    }

    if (!mounted ||
        _micLocked ||
        restartGeneration != _speechGeneration) {
      return;
    }

    _setListeningState(false);

    await Future.delayed(delay);

    if (!mounted ||
        _micLocked ||
        _processingVoiceCommand ||
        restartGeneration != _speechGeneration) {
      return;
    }

    await _startMic();
  }

  // ---------------------------------------------------------------------------
  // STOP MIC
  // ---------------------------------------------------------------------------

  Future<void> _stopMic({
    bool invalidateSession = true,
  }) async {
    if (invalidateSession) {
      _speechGeneration++;
    }

    _micRestartTimer?.cancel();
    _micRestartTimer = null;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        '🎙️ MIC STOP ERROR: $e',
      );
    }

    if (!mounted) {
      return;
    }

    _setListeningState(false);

    if (mounted) {
      _micController.stop();
      _micController.value = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // NLP INTENT ENGINE
  // ---------------------------------------------------------------------------

  void _handleNlpCommand(
      String speech, {
        int? expectedGeneration,
      }) {
    if (_micLocked ||
        _processingVoiceCommand) {
      return;
    }

    if (expectedGeneration != null &&
        expectedGeneration != _speechGeneration) {
      return;
    }

    final text = speech
        .replaceAll(
      RegExp(r'[^\w\s]'),
      '',
    )
        .toLowerCase()
        .trim();

    bool commandExecuted = false;

    // -----------------------------------------------------------------------
    // NEXT
    // -----------------------------------------------------------------------

    if (_containsAny(
      text,
      [
        'next',
        'forward',
        'next image',
        'next picture',
        'show next',
        'go next',
      ],
    )) {
      _nextImage();

      _setVoiceFeedback(
        _currentIndex < widget.imageUrls.length - 1
            ? 'Moving to next image'
            : 'Already at last image',
      );

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // PREVIOUS
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'previous',
        'back',
        'go back',
        'previous image',
        'previous picture',
        'show previous',
      ],
    )) {
      _previousImage();

      _setVoiceFeedback(
        _currentIndex > 0
            ? 'Moving to previous image'
            : 'Already at first image',
      );

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // ZOOM IN
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'zoom in',
        'enlarge',
        'magnify',
        'zoom closer',
        'make bigger',
      ],
    )) {
      _zoomIn();

      _setVoiceFeedback(
        'Zooming in',
      );

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // ZOOM OUT
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'zoom out',
        'reduce',
        'minimize',
        'zoom away',
        'make smaller',
      ],
    )) {
      _zoomOut();

      _setVoiceFeedback(
        'Zooming out',
      );

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // RESET
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'reset',
        'reset zoom',
        'normal view',
        'fit image',
        'reset image',
      ],
    )) {
      _resetZoom();

      _setVoiceFeedback(
        'Image view reset',
      );

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // HIDE CONTROLS
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'hide controls',
        'hide interface',
        'clean view',
        'minimal view',
      ],
    )) {
      _toggleControls();

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // SHOW CONTROLS
    // -----------------------------------------------------------------------

    else if (_containsAny(
      text,
      [
        'show controls',
        'show interface',
        'show buttons',
      ],
    )) {
      if (!_showControls) {
        _toggleControls();
      }

      commandExecuted = true;
    }

    // -----------------------------------------------------------------------
    // COMMAND COMPLETED
    // -----------------------------------------------------------------------

    if (commandExecuted) {
      _processingVoiceCommand = true;

      _micRestartTimer?.cancel();

      final int commandGeneration = _speechGeneration;

      Future<void>(() async {
        try {
          // Stop the current recognition session, but do NOT invalidate
          // the command generation. This is important because the command
          // itself is still valid and must be followed by another session.
          try {
            if (_speech.isListening) {
              await _speech.stop();
            }
          } catch (e) {
            debugPrint(
              '🎙️ Command session stop error: $e',
            );
          }

          if (mounted &&
              !_micLocked &&
              commandGeneration == _speechGeneration) {
            _setListeningState(false);
          }

          await Future.delayed(
            const Duration(
              milliseconds: 300,
            ),
          );

          if (!mounted ||
              _micLocked ||
              commandGeneration != _speechGeneration) {
            return;
          }

          _processingVoiceCommand = false;

          await _startMic();
        } catch (e, stackTrace) {
          debugPrint(
            '🎙️ Command restart error: $e',
          );

          debugPrintStack(
            stackTrace: stackTrace,
          );

          if (mounted &&
              !_micLocked &&
              commandGeneration == _speechGeneration) {
            _processingVoiceCommand = false;

            _scheduleMicRestart(
              delay: const Duration(
                milliseconds: 500,
              ),
            );
          }
        }
      });
    }
  }

  bool _containsAny(
      String text,
      List<String> phrases,
      ) {
    for (final phrase in phrases) {
      if (text.contains(phrase)) {
        return true;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // IMAGE CONTROLS
  // ---------------------------------------------------------------------------

  void _nextImage() {
    if (_currentIndex >= widget.imageUrls.length - 1) {
      _showBoundaryFeedback(
        'Last image',
      );

      return;
    }

    setState(() {
      _isChangingPage = true;
    });

    _pageController.nextPage(
      duration: const Duration(
        milliseconds: 450,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  void _previousImage() {
    if (_currentIndex <= 0) {
      _showBoundaryFeedback(
        'First image',
      );

      return;
    }

    setState(() {
      _isChangingPage = true;
    });

    _pageController.previousPage(
      duration: const Duration(
        milliseconds: 450,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToImage(int index) {
    if (index < 0 ||
        index >= widget.imageUrls.length ||
        index == _currentIndex) {
      return;
    }

    setState(() {
      _isChangingPage = true;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(
        milliseconds: 500,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------------------------------------------------------------------------
  // ZOOM
  // ---------------------------------------------------------------------------

  static const double _minZoomScale = 0.5;
  static const double _maxZoomScale = 6.0;
  static const double _zoomStep = 1.25;

  void _zoomIn() {
    if (!mounted ||
        widget.imageUrls.isEmpty) {
      return;
    }

    final controller = _controllerFor(
      _currentIndex,
    );

    final currentScale =
        controller.scale ?? 1.0;

    final nextScale = (currentScale * _zoomStep).clamp(
      _minZoomScale,
      _maxZoomScale,
    );

    controller.scale = nextScale;
  }

  void _zoomOut() {
    if (!mounted ||
        widget.imageUrls.isEmpty) {
      return;
    }

    final controller = _controllerFor(
      _currentIndex,
    );

    final currentScale =
        controller.scale ?? 1.0;

    final nextScale = (currentScale / _zoomStep).clamp(
      _minZoomScale,
      _maxZoomScale,
    );

    controller.scale = nextScale;
  }

  void _resetZoom() {
    if (!mounted ||
        widget.imageUrls.isEmpty) {
      return;
    }

    final controller = _controllerFor(
      _currentIndex,
    );

    controller.reset();

    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // PAGE CHANGED
  // ---------------------------------------------------------------------------

  void _onPageChanged(int index) {
    if (!mounted) {
      return;
    }

    setState(() {
      _currentIndex = index;
      _isChangingPage = false;

      _updateProgress();
    });

    _imageController
      ..reset()
      ..forward();

    _showTemporaryControls();

    debugPrint(
      '🖼️ Current image: ${index + 1}',
    );
  }

  // ---------------------------------------------------------------------------
  // CONTROLS VISIBILITY
  // ---------------------------------------------------------------------------

  void _toggleControls() {
    if (!mounted) {
      return;
    }

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _controlsController.forward();
    } else {
      _controlsController.reverse();
    }
  }

  void _showTemporaryControls() {
    if (!mounted) {
      return;
    }

    setState(() {
      _showControls = true;
    });

    _controlsController.forward();

    _hudHideTimer?.cancel();

    _hudHideTimer = Timer(
      const Duration(
        seconds: 5,
      ),
          () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });

          _controlsController.reverse();
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FEEDBACK
  // ---------------------------------------------------------------------------

  void _setVoiceFeedback(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _voiceFeedback = message;
    });

    _feedbackTimer?.cancel();

    _feedbackTimer = Timer(
      const Duration(
        seconds: 3,
      ),
          () {
        if (mounted) {
          setState(() {
            _voiceFeedback = _isListening
                ? 'Listening for command...'
                : 'Voice assistant ready';
          });
        }
      },
    );
  }

  void _showBoundaryFeedback(String message) {
    _setVoiceFeedback(message);
  }

  // ---------------------------------------------------------------------------
  // KEYBOARD
  // ---------------------------------------------------------------------------

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowRight) {
      _nextImage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowLeft) {
      _previousImage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.equal ||
        event.logicalKey ==
            LogicalKeyboardKey.add) {
      _zoomIn();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.minus) {
      _zoomOut();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.digit0) {
      _resetZoom();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.space) {
      _toggleControls();
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // BACK / EXIT
  // ---------------------------------------------------------------------------
  //
  // IMPORTANT:
  // Do not await speech_to_text.stop() before popping the route.
  //
  // speech_to_text may take time to finish its platform-side shutdown.
  // Waiting for it here can make Android back appear completely unresponsive.
  //
  // We therefore:
  //   1. Lock the microphone session.
  //   2. Invalidate pending recognition callbacks.
  //   3. Cancel timers.
  //   4. Start microphone cleanup without blocking navigation.
  //   5. Immediately allow Navigator to pop the route.
  //

  void _prepareForExit() {
    if (_micLocked) {
      return;
    }

    _micLocked = true;
    _processingVoiceCommand = false;

    // Invalidate every pending recognition callback.
    _speechGeneration++;

    _startDelayTimer?.cancel();
    _startDelayTimer = null;

    _micRestartTimer?.cancel();
    _micRestartTimer = null;

    _feedbackTimer?.cancel();
    _feedbackTimer = null;

    _hudHideTimer?.cancel();
    _hudHideTimer = null;

    // Do not await this.
    //
    // The route must be allowed to pop immediately. dispose() will perform
    // the final synchronous controller cleanup after the route is removed.
    _stopMic(
      invalidateSession: false,
    );
  }

  // Called by WillPopScope for Android/system back.
  Future<bool> _onBackPressed() async {
    if (_micLocked) {
      return false;
    }

    _prepareForExit();

    // IMPORTANT:
    // Returning true tells Flutter to pop this route itself.
    // We do NOT call Navigator.pop() here.
    return true;
  }

  // Called by the visible top-left Back button.
  void _onBackButtonPressed() {
    if (_micLocked) {
      return;
    }

    _prepareForExit();

    // Pop immediately instead of waiting for speech recognition shutdown.
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _micLocked = true;
    _processingVoiceCommand = false;

    // Invalidate all pending speech callbacks.
    _speechGeneration++;

    _startDelayTimer?.cancel();
    _startDelayTimer = null;

    _micRestartTimer?.cancel();
    _micRestartTimer = null;

    _feedbackTimer?.cancel();
    _feedbackTimer = null;

    _hudHideTimer?.cancel();
    _hudHideTimer = null;

    // -------------------------------------------------------------------------
    // FINAL SPEECH CLEANUP
    // -------------------------------------------------------------------------
    //
    // Do not call _stopMic() here because it awaits speech.stop() and then
    // attempts to manipulate the animation controller. By this point dispose
    // is already tearing down the widget's controllers.
    //
    // Stop speech directly and do not await it.
    //

    try {
      if (_speech.isListening) {
        _speech.stop();
      }

      _speech.cancel();
    } catch (_) {}

    // Stop animation before disposing it.
    _micController.stop();

    _pageController.dispose();

    for (final controller
    in _photoControllers.values) {
      controller.dispose();
    }

    _photoControllers.clear();

    _entranceController.dispose();
    _hudController.dispose();
    _micController.dispose();
    _controlsController.dispose();
    _imageController.dispose();

    _keyboardFocusNode.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return _buildEmptyState();
    }

    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        backgroundColor: _background,
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            children: [
              // -----------------------------------------------------------------
              // IMAGE BACKGROUND
              // -----------------------------------------------------------------

              Positioned.fill(
                child: GestureDetector(
                  behavior:
                  HitTestBehavior.translucent,
                  onTap: _showTemporaryControls,
                  child: Container(
                    color: Colors.black,
                    child: PageView.builder(
                      controller: _pageController,
                      physics:
                      const BouncingScrollPhysics(),
                      itemCount:
                      widget.imageUrls.length,
                      onPageChanged:
                      _onPageChanged,
                      itemBuilder:
                          (context, index) {
                        return _buildImage(index);
                      },
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------------
              // TOP GRADIENT
              // -----------------------------------------------------------------

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 190,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: 350,
                    ),
                    opacity:
                    _showControls ? 1 : 0,
                    child: Container(
                      decoration:
                      const BoxDecoration(
                        gradient:
                        LinearGradient(
                          begin:
                          Alignment.topCenter,
                          end:
                          Alignment.bottomCenter,
                          colors: [
                            Color(0xD902080D),
                            Color(0x9002080D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------------
              // BOTTOM GRADIENT
              // -----------------------------------------------------------------

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 230,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: 350,
                    ),
                    opacity:
                    _showControls ? 1 : 0,
                    child: Container(
                      decoration:
                      const BoxDecoration(
                        gradient:
                        LinearGradient(
                          begin:
                          Alignment.bottomCenter,
                          end:
                          Alignment.topCenter,
                          colors: [
                            Color(0xE802080D),
                            Color(0xA002080D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------------
              // TOP HUD
              // -----------------------------------------------------------------

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: _buildTopHud(),
                ),
              ),

              // -----------------------------------------------------------------
              // SIDE NAVIGATION
              // -----------------------------------------------------------------

              Positioned(
                left: 22,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Center(
                    child:
                    _buildNavigationButton(
                      icon:
                      Icons.chevron_left_rounded,
                      enabled:
                      _currentIndex > 0,
                      onPressed:
                      _previousImage,
                    ),
                  ),
                ),
              ),

              Positioned(
                right: 22,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Center(
                    child:
                    _buildNavigationButton(
                      icon:
                      Icons.chevron_right_rounded,
                      enabled:
                      _currentIndex <
                          widget.imageUrls.length -
                              1,
                      onPressed:
                      _nextImage,
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------------
              // BOTTOM CONTROLS
              // -----------------------------------------------------------------

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child:
                  _buildBottomControls(),
                ),
              ),

              // -----------------------------------------------------------------
              // VOICE FEEDBACK
              // -----------------------------------------------------------------

              Positioned(
                left: 0,
                right: 0,
                bottom:
                _showFilmstrip ? 148 : 76,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: 300,
                    ),
                    opacity:
                    _showControls ? 1 : 0,
                    child: Center(
                      child:
                      _buildVoiceFeedback(),
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------------
              // LOADING OVERLAY
              // -----------------------------------------------------------------

              if (_isChangingPage)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE
  // ---------------------------------------------------------------------------

  Widget _buildImage(int index) {
    final controller = _controllerFor(index);

    return AnimatedBuilder(
      animation: _imageController,
      builder: (context, child) {
        final curved =
        Curves.easeOutCubic.transform(
          _imageController.value,
        );

        return Opacity(
          opacity:
          curved.clamp(0.0, 1.0),
          child: Transform.scale(
            scale:
            0.985 + (curved * 0.015),
            child: child,
          ),
        );
      },
      child: PhotoView(
        controller: controller,
        imageProvider: NetworkImage(
          widget.imageUrls[index],
        ),
        backgroundDecoration:
        const BoxDecoration(
          color: Colors.black,
        ),
        minScale:
        PhotoViewComputedScale.contained,
        maxScale:
        PhotoViewComputedScale.covered * 4,
        initialScale:
        PhotoViewComputedScale.contained,
        heroAttributes:
        PhotoViewHeroAttributes(
          tag: 'clinical-image-$index',
        ),
        loadingBuilder:
            (context, event) {
          final expected =
              event?.expectedTotalBytes;

          final loaded =
              event?.cumulativeBytesLoaded ??
                  0;

          final progress =
          expected != null &&
              expected > 0
              ? loaded / expected
              : null;

          return Center(
            child:
            _buildImageLoading(progress),
          );
        },
        errorBuilder:
            (context, error, stackTrace) {
          return _buildImageError();
        },
      ),
    );
  }

  Widget _buildImageLoading(
      double? progress,
      ) {
    return Container(
      width: 180,
      padding:
      const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.92),
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color:
          _cyan.withOpacity(0.12),
        ),
      ),
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child:
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              color: _cyan,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Loading image',
            style: GoogleFonts.inter(
              color: _white,
              fontSize: 12,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Clinical imaging',
            style: GoogleFonts.inter(
              color: _mutedText,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageError() {
    return Center(
      child: Container(
        margin:
        const EdgeInsets.all(30),
        padding:
        const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius:
          BorderRadius.circular(22),
          border: Border.all(
            color: Colors.redAccent
                .withOpacity(0.15),
          ),
        ),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .broken_image_outlined,
              color: Colors.redAccent
                  .withOpacity(0.85),
              size: 38,
            ),
            const SizedBox(height: 14),
            Text(
              'Unable to load image',
              style:
              GoogleFonts.poppins(
                color: _white,
                fontSize: 14,
                fontWeight:
                FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Please check the image source.',
              style:
              GoogleFonts.inter(
                color: _mutedText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP HUD
  // ---------------------------------------------------------------------------

  Widget _buildTopHud() {
    return AnimatedSlide(
      duration:
      const Duration(milliseconds: 350),
      curve:
      Curves.easeOutCubic,
      offset: _showControls
          ? Offset.zero
          : const Offset(0, -0.25),
      child: AnimatedOpacity(
        duration:
        const Duration(milliseconds: 300),
        opacity:
        _showControls ? 1 : 0,
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            0,
          ),
          child: Row(
            children: [
              _buildGlassButton(
                icon:
                Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed:
                _onBackButtonPressed,
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                _buildClinicalHeader(),
              ),
              const SizedBox(width: 12),
              _buildMicStatus(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClinicalHeader() {
    return Container(
      height: 58,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 17,
      ),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.84),
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.075),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.28),
            blurRadius: 25,
            offset:
            const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration:
            BoxDecoration(
              color:
              _cyan.withOpacity(0.10),
              borderRadius:
              BorderRadius.circular(
                10,
              ),
              border: Border.all(
                color: _cyan
                    .withOpacity(0.12),
              ),
            ),
            child: const Icon(
              Icons.image_outlined,
              color: _cyan,
              size: 17,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'CLINICAL IMAGING',
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.inter(
                    color: _mutedText,
                    fontSize: 8.5,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Image ${_currentIndex + 1} of ${widget.imageUrls.length}',
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.poppins(
                    color: _white,
                    fontSize: 14,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildImageCounter(),
        ],
      ),
    );
  }

  Widget _buildImageCounter() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white
            .withOpacity(0.045),
        borderRadius:
        BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.06),
        ),
      ),
      child: Text(
        '${(_currentIndex + 1).toString().padLeft(2, '0')}'
            ' / '
            '${widget.imageUrls.length.toString().padLeft(2, '0')}',
        style: GoogleFonts.inter(
          color: _secondaryText,
          fontSize: 10,
          fontWeight:
          FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MIC STATUS
  // ---------------------------------------------------------------------------

  Widget _buildMicStatus() {
    return AnimatedBuilder(
      animation: _micController,
      builder: (context, child) {
        final pulse = _isListening
            ? 1.0 +
            (_micController.value *
                0.06)
            : 1.0;

        return Transform.scale(
          scale: pulse,
          child: Container(
            height: 58,
            padding:
            const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            decoration:
            BoxDecoration(
              color:
              _surface.withOpacity(0.84),
              borderRadius:
              BorderRadius.circular(18),
              border: Border.all(
                color:
                (_isListening
                    ? _cyan
                    : Colors.white)
                    .withOpacity(
                  _isListening
                      ? 0.18
                      : 0.075,
                ),
              ),
            ),
            child: Row(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Stack(
                  alignment:
                  Alignment.center,
                  children: [
                    if (_isListening)
                      Container(
                        width: 31,
                        height: 31,
                        decoration:
                        BoxDecoration(
                          shape:
                          BoxShape.circle,
                          color: _cyan
                              .withOpacity(
                            0.08 +
                                (_micController
                                    .value *
                                    0.06),
                          ),
                        ),
                      ),
                    Icon(
                      _isListening
                          ? Icons
                          .mic_rounded
                          : Icons
                          .mic_none_rounded,
                      color: _isListening
                          ? _cyan
                          : _mutedText,
                      size: 17,
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                if (MediaQuery.of(context)
                    .size
                    .width >
                    560)
                  Text(
                    _isListening
                        ? 'LISTENING'
                        : 'VOICE READY',
                    style:
                    GoogleFonts.inter(
                      color: _isListening
                          ? _cyan
                          : _secondaryText,
                      fontSize: 9,
                      fontWeight:
                      FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildNavigationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return AnimatedOpacity(
      duration:
      const Duration(milliseconds: 250),
      opacity: enabled ? 1 : 0.28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(18),
          onTap:
          enabled ? onPressed : null,
          child: Container(
            width: 48,
            height: 86,
            decoration:
            BoxDecoration(
              color:
              _surface.withOpacity(0.74),
              borderRadius:
              BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white
                    .withOpacity(0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(0.30),
                  blurRadius: 18,
                  offset:
                  const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: _white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE FEEDBACK
  // ---------------------------------------------------------------------------

  Widget _buildVoiceFeedback() {
    return Container(
      constraints:
      const BoxConstraints(
        maxWidth: 380,
      ),
      margin:
      const EdgeInsets.symmetric(
        horizontal: 20,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.90),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: _isListening
              ? _cyan.withOpacity(0.16)
              : Colors.white
              .withOpacity(0.06),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _micController,
            builder: (context, child) {
              return Container(
                width: 7,
                height: 7,
                decoration:
                BoxDecoration(
                  color: _isListening
                      ? _cyan
                      : _mutedText,
                  shape:
                  BoxShape.circle,
                  boxShadow: _isListening
                      ? [
                    BoxShadow(
                      color: _cyan
                          .withOpacity(
                        0.25 +
                            (_micController
                                .value *
                                0.25),
                      ),
                      blurRadius: 8,
                    ),
                  ]
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              _voiceFeedback,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              textAlign:
              TextAlign.center,
              style: GoogleFonts.inter(
                color: _secondaryText,
                fontSize: 10,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM CONTROLS
  // ---------------------------------------------------------------------------

  Widget _buildBottomControls() {
    return AnimatedSlide(
      duration:
      const Duration(milliseconds: 350),
      curve:
      Curves.easeOutCubic,
      offset: _showControls
          ? Offset.zero
          : const Offset(0, 0.35),
      child: AnimatedOpacity(
        duration:
        const Duration(milliseconds: 300),
        opacity:
        _showControls ? 1 : 0,
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            12,
          ),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              if (_showFilmstrip)
                _buildFilmstrip(),

              const SizedBox(height: 10),

              _buildControlBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILMSTRIP
  // ---------------------------------------------------------------------------

  Widget _buildFilmstrip() {
    return Container(
      height: 74,
      padding:
      const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.86),
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.065),
        ),
      ),
      child: ListView.separated(
        scrollDirection:
        Axis.horizontal,
        physics:
        const BouncingScrollPhysics(),
        itemCount:
        widget.imageUrls.length,
        separatorBuilder:
            (_, __) =>
        const SizedBox(width: 7),
        itemBuilder:
            (context, index) {
          final selected =
              index == _currentIndex;

          return GestureDetector(
            onTap:
                () => _goToImage(index),
            child:
            AnimatedContainer(
              duration:
              const Duration(
                milliseconds: 250,
              ),
              curve:
              Curves.easeOutCubic,
              width:
              selected ? 84 : 68,
              decoration:
              BoxDecoration(
                borderRadius:
                BorderRadius.circular(
                  11,
                ),
                border: Border.all(
                  color: selected
                      ? _cyan
                      : Colors.white
                      .withOpacity(
                    0.06,
                  ),
                  width:
                  selected ? 1.5 : 1,
                ),
              ),
              clipBehavior:
              Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.imageUrls[index],
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) {
                      return Container(
                        color:
                        _surfaceLight,
                        child: const Icon(
                          Icons
                              .broken_image_outlined,
                          color:
                          _mutedText,
                          size: 18,
                        ),
                      );
                    },
                    loadingBuilder: (
                        context,
                        child,
                        progress,
                        ) {
                      if (progress ==
                          null) {
                        return child;
                      }

                      return Container(
                        color:
                        _surfaceLight,
                        child:
                        const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child:
                            CircularProgressIndicator(
                              strokeWidth:
                              1.5,
                              color:
                              _cyan,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (selected)
                    Positioned.fill(
                      child:
                      DecoratedBox(
                        decoration:
                        BoxDecoration(
                          gradient:
                          LinearGradient(
                            begin:
                            Alignment
                                .topCenter,
                            end:
                            Alignment
                                .bottomCenter,
                            colors: [
                              _cyan
                                  .withOpacity(
                                0.03,
                              ),
                              _cyan
                                  .withOpacity(
                                0.16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 5,
                    bottom: 4,
                    child: Container(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration:
                      BoxDecoration(
                        color: Colors.black
                            .withOpacity(
                          0.65,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          5,
                        ),
                      ),
                      child: Text(
                        '${index + 1}',
                        style:
                        GoogleFonts.inter(
                          color: _white,
                          fontSize: 8,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTROL BAR
  // ---------------------------------------------------------------------------

  Widget _buildControlBar() {
    return Container(
      height: 62,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.94),
        borderRadius:
        BorderRadius.circular(19),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.30),
            blurRadius: 25,
            offset:
            const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildControlButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            onPressed: _zoomOut,
          ),

          _buildZoomLabel(),

          _buildControlButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            onPressed: _zoomIn,
          ),

          const SizedBox(width: 6),

          Container(
            width: 1,
            height: 27,
            color: Colors.white
                .withOpacity(0.07),
          ),

          const SizedBox(width: 6),

          _buildControlButton(
            icon:
            Icons.fit_screen_rounded,
            tooltip: 'Reset view',
            onPressed: _resetZoom,
          ),

          _buildControlButton(
            icon: _showFilmstrip
                ? Icons
                .view_carousel_rounded
                : Icons
                .view_carousel_outlined,
            tooltip:
            'Toggle thumbnails',
            onPressed: () {
              setState(() {
                _showFilmstrip =
                !_showFilmstrip;
              });
            },
          ),

          const Spacer(),

          if (MediaQuery.of(context)
              .size
              .width >
              620)
            Expanded(
              flex: 2,
              child: Padding(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 18,
                ),
                child:
                _buildProgressBar(),
              ),
            ),

          const Spacer(),

          _buildControlButton(
            icon: _showControls
                ? Icons
                .visibility_off_outlined
                : Icons
                .visibility_outlined,
            tooltip:
            'Toggle controls',
            onPressed:
            _toggleControls,
          ),

          const SizedBox(width: 5),

          _buildControlButton(
            icon:
            Icons.arrow_back_rounded,
            tooltip: 'Previous',
            enabled:
            _currentIndex > 0,
            onPressed:
            _previousImage,
          ),

          _buildControlButton(
            icon:
            Icons.arrow_forward_rounded,
            tooltip: 'Next',
            enabled: _currentIndex <
                widget.imageUrls.length -
                    1,
            onPressed: _nextImage,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ZOOM LABEL
  // ---------------------------------------------------------------------------
  //
  // PhotoViewController exposes its state through outputStateStream in the
  // installed photo_view version.
  //
  // StreamBuilder therefore keeps the zoom percentage synchronized with
  // programmatic zooming as well as PhotoView's own zoom gestures.
  // ---------------------------------------------------------------------------

  Widget _buildZoomLabel() {
    final controller =
    _controllerFor(_currentIndex);

    return StreamBuilder<
        PhotoViewControllerValue>(
      stream:
      controller.outputStateStream,
      initialData:
      controller.value,
      builder:
          (context, snapshot) {
        final scale =
            snapshot.data?.scale ??
                controller.scale ??
                1.0;

        final percentage =
        (scale * 100).round();

        return Container(
          constraints:
          const BoxConstraints(
            minWidth: 48,
          ),
          alignment:
          Alignment.center,
          child: Text(
            '$percentage%',
            style:
            GoogleFonts.inter(
              color:
              _secondaryText,
              fontSize: 9.5,
              fontWeight:
              FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // CONTROL BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration:
      const Duration(
        milliseconds: 500,
      ),
      child: AnimatedOpacity(
        duration:
        const Duration(milliseconds: 200),
        opacity:
        enabled ? 1 : 0.30,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius:
            BorderRadius.circular(13),
            onTap:
            enabled ? onPressed : null,
            child: SizedBox(
              width: 42,
              height: 46,
              child: Icon(
                icon,
                color: enabled
                    ? _white
                    : _mutedText,
                size: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROGRESS BAR
  // ---------------------------------------------------------------------------

  Widget _buildProgressBar() {
    return Column(
      mainAxisAlignment:
      MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              'IMAGE',
              style: GoogleFonts.inter(
                color: _mutedText,
                fontSize: 7.5,
                fontWeight:
                FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            Text(
              '${_currentIndex + 1}/${widget.imageUrls.length}',
              style: GoogleFonts.inter(
                color: _secondaryText,
                fontSize: 8,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius:
          BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(
                height: 4,
                decoration:
                BoxDecoration(
                  color: Colors.white
                      .withOpacity(0.06),
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                ),
              ),
              AnimatedFractionallySizedBox(
                duration:
                const Duration(
                  milliseconds: 450,
                ),
                curve:
                Curves.easeOutCubic,
                widthFactor:
                _imageProgress,
                child: Container(
                  height: 4,
                  decoration:
                  BoxDecoration(
                    color: _cyan,
                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _cyan
                            .withOpacity(
                          0.35,
                        ),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // GLASS BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildGlassButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration:
      const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            width: 58,
            height: 58,
            decoration:
            BoxDecoration(
              color:
              _surface.withOpacity(0.84),
              borderRadius:
              BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white
                    .withOpacity(0.075),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(0.25),
                  blurRadius: 22,
                  offset:
                  const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: _white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY STATE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: _background,
      body: Center(
        child: Container(
          margin:
          const EdgeInsets.all(24),
          padding:
          const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius:
            BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white
                  .withOpacity(0.07),
            ),
          ),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration:
                BoxDecoration(
                  color: _cyan
                      .withOpacity(0.08),
                  shape:
                  BoxShape.circle,
                ),
                child: const Icon(
                  Icons
                      .image_not_supported_outlined,
                  color: _cyan,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No clinical images',
                style:
                GoogleFonts.poppins(
                  color: _white,
                  fontSize: 17,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'There are no images available to display.',
                textAlign:
                TextAlign.center,
                style: GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(
                  Icons
                      .arrow_back_rounded,
                  size: 17,
                ),
                label:
                const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}