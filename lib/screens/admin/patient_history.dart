import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../iamgeview_page.dart';
import '../pdfview_page.dart';
import '../surgeon/surgeon_dashboard.dart';

class PatientHistoryPage extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientData;

  const PatientHistoryPage({
    Key? key,
    required this.patientId,
    required this.patientData,
  }) : super(key: key);

  @override
  State<PatientHistoryPage> createState() => _PatientHistoryPageState();
}

class _PatientHistoryPageState extends State<PatientHistoryPage>
    with TickerProviderStateMixin {
  // ===========================================================================
  // THEME
  // ===========================================================================

  static const Color _background = Color(0xFF071521);
  static const Color _backgroundSecondary = Color(0xFF0B1F33);
  static const Color _card = Color(0xFF0D2435);
  static const Color _cardSecondary = Color(0xFF102A3D);

  static const Color _navyBlue = Color(0xFF123A56);
  static const Color _teal = Color(0xFF0E7490);
  static const Color _cyan = Color(0xFF22D3EE);

  static const Color _mutedText = Color(0xFF8EA5B4);
  static const Color _secondaryText = Color(0xFFB7C7D1);

  static const Color _danger = Color(0xFFDC2626);
  static const Color _success = Color(0xFF22C55E);

  // ===========================================================================
  // SPEECH
  // ===========================================================================

  late final stt.SpeechToText _speech;

  bool _speechInitialized = false;
  bool _isListening = false;
  bool _isProcessingCommand = false;

  // Prevents overlapping asynchronous microphone starts.
  bool _isStartingMicrophone = false;

  // Prevents speech callbacks from finishing the same session twice.
  bool _isFinishingListening = false;

  /// Monotonically increasing generation.
  ///
  /// Every time the speech lifecycle changes, this value is incremented.
  /// Any asynchronous callback belonging to an older generation is ignored.
  ///
  /// This is especially important during navigation because speech_to_text
  /// can still deliver callbacks after stop/cancel has been requested.
  int _speechGeneration = 0;

  /// Prevents the microphone from ever restarting after document navigation
  /// or leaving this page.
  bool _micLocked = false;
  bool _micPermanentlyDisabled = false;

  String _voiceText = '';
  String? _voiceError;

  Timer? _initializationTimer;
  Timer? _silenceTimer;
  Timer? _maximumListeningTimer;
  Timer? _minimumListeningTimer;

  static const Duration _initialMicDelay =
  Duration(milliseconds: 900);

  /// The microphone must remain active for at least six seconds after
  /// automatically starting on this page.
  static const Duration _minimumListeningDuration =
  Duration(seconds: 6);

  /// After the six-second minimum has elapsed, silence can stop recognition.
  static const Duration _silenceTimeout =
  Duration(seconds: 2);

  /// Absolute upper limit for one listening session.
  static const Duration _maximumListeningDuration =
  Duration(seconds: 15);

  bool _minimumListeningPeriodCompleted = false;

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  bool _isNavigating = false;

  // ===========================================================================
  // DOCUMENTS
  // ===========================================================================

  late final List<dynamic> _documents;

  // ===========================================================================
  // ASSIGNED DOCTOR
  // ===========================================================================

  String _assignedDoctorName = 'Loading...';
  bool _doctorNameLoading = false;

  // ===========================================================================
  // SCROLL
  // ===========================================================================

  final ScrollController _scrollController =
  ScrollController();

  final GlobalKey _documentsKey = GlobalKey();

  // ===========================================================================
  // ANIMATIONS
  // ===========================================================================

  late AnimationController _pageController;
  late AnimationController _heroController;
  late AnimationController _pulseController;

  late Animation<double> _pageFade;
  late Animation<Offset> _heroSlide;
  late Animation<double> _heroFade;
  late Animation<double> _micPulse;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    _documents = _extractDocuments();

    _assignedDoctorName =
        _getInitiallyAvailableDoctorName();

    _initializeAnimations();

    // Resolve the doctor's name independently from the UI animation.
    _loadAssignedDoctorName();

    // Initialize the speech system after the page has had time to stabilize.
    _initializationTimer = Timer(
      _initialMicDelay,
      _startInitialMicrophone,
    );
  }

  // ===========================================================================
  // ANIMATIONS
  // ===========================================================================

  void _initializeAnimations() {
    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pageFade = CurvedAnimation(
      parent: _pageController,
      curve: Curves.easeOutCubic,
    );

    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _heroController,
        curve: Curves.easeOutCubic,
      ),
    );

    _heroFade = CurvedAnimation(
      parent: _heroController,
      curve: Curves.easeOut,
    );

    _micPulse = Tween<double>(
      begin: 1.0,
      end: 1.10,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _pageController.forward();

    Future.delayed(
      const Duration(milliseconds: 100),
          () {
        if (mounted) {
          _heroController.forward();
        }
      },
    );
  }

  // ===========================================================================
  // ASSIGNED DOCTOR NAME
  // ===========================================================================

  String _getInitiallyAvailableDoctorName() {
    final directName =
    widget.patientData['assignedDoctorName'];

    if (directName != null) {
      final value = directName.toString().trim();

      if (value.isNotEmpty) {
        return value;
      }
    }

    final alternativeName =
    widget.patientData['doctorName'];

    if (alternativeName != null) {
      final value = alternativeName.toString().trim();

      if (value.isNotEmpty) {
        return value;
      }
    }

    return 'Loading...';
  }

  Future<void> _loadAssignedDoctorName() async {
    if (_doctorNameLoading) {
      return;
    }

    _doctorNameLoading = true;

    try {
      final existingName =
      widget.patientData['assignedDoctorName'];

      if (existingName != null) {
        final name = existingName.toString().trim();

        if (name.isNotEmpty) {
          if (mounted) {
            setState(() {
              _assignedDoctorName = name;
            });
          }

          return;
        }
      }

      final alternativeName =
      widget.patientData['doctorName'];

      if (alternativeName != null) {
        final name = alternativeName.toString().trim();

        if (name.isNotEmpty) {
          if (mounted) {
            setState(() {
              _assignedDoctorName = name;
            });
          }

          return;
        }
      }

      final assignedDoctor =
      widget.patientData['assignedDoctor'];

      if (assignedDoctor == null) {
        if (mounted) {
          setState(() {
            _assignedDoctorName = 'Not assigned';
          });
        }

        return;
      }

      final doctorId =
      assignedDoctor.toString().trim();

      if (doctorId.isEmpty) {
        if (mounted) {
          setState(() {
            _assignedDoctorName = 'Not assigned';
          });
        }

        return;
      }

      if (!_looksLikeFirebaseUid(doctorId)) {
        if (mounted) {
          setState(() {
            _assignedDoctorName = doctorId;
          });
        }

        return;
      }

      final doctorSnapshot =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(doctorId)
          .get();

      if (!doctorSnapshot.exists) {
        if (mounted) {
          setState(() {
            _assignedDoctorName =
            'Doctor not found';
          });
        }

        return;
      }

      final doctorData =
      doctorSnapshot.data();

      if (doctorData == null) {
        if (mounted) {
          setState(() {
            _assignedDoctorName =
            'Doctor not found';
          });
        }

        return;
      }

      final resolvedName =
      _firstNonEmptyValue(
        [
          doctorData['name'],
          doctorData['fullName'],
          doctorData['displayName'],
          doctorData['doctorName'],
        ],
      );

      if (mounted) {
        setState(() {
          _assignedDoctorName =
              resolvedName ?? 'Doctor not found';
        });
      }
    } catch (e) {
      debugPrint(
        'Error loading assigned doctor name: $e',
      );

      if (mounted) {
        setState(() {
          _assignedDoctorName =
          'Unable to load doctor';
        });
      }
    } finally {
      _doctorNameLoading = false;
    }
  }

  String? _firstNonEmptyValue(
      List<dynamic> values,
      ) {
    for (final value in values) {
      if (value == null) {
        continue;
      }

      final stringValue =
      value.toString().trim();

      if (stringValue.isNotEmpty) {
        return stringValue;
      }
    }

    return null;
  }

  bool _looksLikeFirebaseUid(
      String value,
      ) {
    return RegExp(
      r'^[A-Za-z0-9]{20,}$',
    ).hasMatch(value);
  }

  // ===========================================================================
  // INITIAL MICROPHONE START
  // ===========================================================================

  Future<void> _startInitialMicrophone() async {
    if (!mounted ||
        _micLocked ||
        _micPermanentlyDisabled ||
        _isNavigating ||
        _isListening ||
        _isStartingMicrophone) {
      return;
    }

    // Automatic startup is allowed only once for this page instance.
    //
    // No callback elsewhere automatically calls _startListening again.
    debugPrint(
      '🎙️ Preparing automatic microphone start...',
    );

    await _startListening(
      automaticStart: true,
    );
  }

  // ===========================================================================
  // SPEECH PREPARATION
  // ===========================================================================

  Future<void> _prepareSpeechRecognition() async {
    if (!mounted ||
        _micLocked ||
        _micPermanentlyDisabled ||
        _speechInitialized) {
      return;
    }

    try {
      final available =
      await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: false,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _speechInitialized = available;

        if (!available) {
          _voiceError =
          'Voice recognition is unavailable on this device.';
        }
      });
    } catch (e) {
      debugPrint(
        'Speech initialization error: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _speechInitialized = false;
        _voiceError =
        'Unable to initialize voice recognition.';
      });
    }
  }

  Future<bool> _prepareSpeechAndReturnAvailability() async {
    if (_speechInitialized) {
      return true;
    }

    try {
      final available =
      await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: false,
      );

      if (!mounted) {
        return false;
      }

      setState(() {
        _speechInitialized = available;
      });

      return available;
    } catch (e) {
      debugPrint(
        'Speech initialization error: $e',
      );

      if (mounted) {
        setState(() {
          _speechInitialized = false;
          _voiceError =
          'Unable to initialize voice recognition.';
        });
      }

      return false;
    }
  }

  // ===========================================================================
  // MICROPHONE
  // ===========================================================================

  Future<void> _toggleMicrophone() async {
    if (_isNavigating ||
        _isProcessingCommand ||
        _isStartingMicrophone ||
        _isFinishingListening ||
        _micLocked ||
        _micPermanentlyDisabled) {
      return;
    }

    if (_isListening) {
      await _stopListening(
        processCommand: true,
        forceStop: true,
      );

      return;
    }

    await _startListening();
  }

  Future<void> _startListening({
    bool automaticStart = false,
  }) async {
    if (!mounted ||
        _isNavigating ||
        _isProcessingCommand ||
        _isListening ||
        _isStartingMicrophone ||
        _micLocked ||
        _micPermanentlyDisabled) {
      return;
    }

    _isStartingMicrophone = true;

    final int generation =
    ++_speechGeneration;

    try {
      // -----------------------------------------------------------------------
      // Permission
      // -----------------------------------------------------------------------

      PermissionStatus permission =
      await Permission.microphone.status;

      if (!mounted ||
          generation != _speechGeneration ||
          _isNavigating ||
          _micLocked ||
          _micPermanentlyDisabled) {
        return;
      }

      if (!permission.isGranted) {
        permission =
        await Permission.microphone.request();
      }

      if (!mounted ||
          generation != _speechGeneration ||
          _isNavigating ||
          _micLocked ||
          _micPermanentlyDisabled) {
        return;
      }

      if (!permission.isGranted) {
        setState(() {
          _voiceError =
          permission.isPermanentlyDenied
              ? 'Microphone permission is permanently denied. Enable it in Settings.'
              : 'Microphone permission is required for voice commands.';
        });

        return;
      }

      // -----------------------------------------------------------------------
      // Initialize speech engine
      // -----------------------------------------------------------------------

      if (!_speechInitialized) {
        final available =
        await _prepareSpeechAndReturnAvailability();

        if (!available ||
            !mounted ||
            generation != _speechGeneration ||
            _isNavigating ||
            _micLocked ||
            _micPermanentlyDisabled) {
          return;
        }
      }

      // -----------------------------------------------------------------------
      // Ensure there is only one active recognition session.
      // -----------------------------------------------------------------------

      if (_speech.isListening) {
        await _safeSpeechStop();
      }

      if (!mounted ||
          generation != _speechGeneration ||
          _isNavigating ||
          _micLocked ||
          _micPermanentlyDisabled) {
        return;
      }

      _silenceTimer?.cancel();
      _maximumListeningTimer?.cancel();
      _minimumListeningTimer?.cancel();

      _minimumListeningPeriodCompleted =
      false;

      setState(() {
        _voiceText = '';
        _voiceError = null;
        _isListening = true;
      });

      _pulseController.repeat(
        reverse: true,
      );

      // -----------------------------------------------------------------------
      // Start recognition
      // -----------------------------------------------------------------------

      await _speech.listen(
        listenFor:
        _maximumListeningDuration,
        pauseFor:
        _silenceTimeout,
        partialResults: true,
        cancelOnError: false,
        listenMode:
        stt.ListenMode.confirmation,
        onResult:
        _handleSpeechResult,
      );

      // -----------------------------------------------------------------------
      // Validate that this is still the active page/session.
      // -----------------------------------------------------------------------

      if (!mounted ||
          generation != _speechGeneration ||
          _isNavigating ||
          _micLocked ||
          _micPermanentlyDisabled) {
        return;
      }

      if (!_speech.isListening) {
        await _finishListening(
          processCommand: false,
        );

        return;
      }

      // -----------------------------------------------------------------------
      // Mandatory six-second listening window
      // -----------------------------------------------------------------------

      _minimumListeningTimer =
          Timer(
            _minimumListeningDuration,
                () async {
              if (!mounted ||
                  generation != _speechGeneration ||
                  !_isListening ||
                  _micLocked ||
                  _isNavigating) {
                return;
              }

              _minimumListeningPeriodCompleted =
              true;

              debugPrint(
                '🎙️ Minimum 6-second microphone period completed.',
              );

              _restartSilenceTimer();
            },
          );

      // -----------------------------------------------------------------------
      // Absolute maximum listening time
      // -----------------------------------------------------------------------

      _maximumListeningTimer =
          Timer(
            _maximumListeningDuration,
                () async {
              if (!mounted ||
                  generation != _speechGeneration ||
                  !_isListening ||
                  _micLocked ||
                  _isNavigating) {
                return;
              }

              await _stopListening(
                processCommand: true,
                forceStop: true,
              );
            },
          );

      debugPrint(
        automaticStart
            ? '🎙️ MIC AUTOMATICALLY STARTED'
            : '🎙️ MIC STARTED',
      );
    } catch (e) {
      debugPrint(
        'Microphone start error: $e',
      );

      if (generation == _speechGeneration &&
          mounted) {
        await _finishListening(
          processCommand: false,
        );

        if (mounted &&
            generation == _speechGeneration) {
          setState(() {
            _voiceError =
            'Unable to start the microphone.';
          });
        }
      }
    } finally {
      if (generation == _speechGeneration) {
        _isStartingMicrophone = false;
      }
    }
  }

  Future<void> _stopListening({
    bool processCommand = true,
    bool forceStop = false,
  }) async {
    // Prevent finalResult, status callbacks and timers from all trying to
    // process the same recognition session simultaneously.
    if (_isFinishingListening) {
      return;
    }

    if (!_isListening &&
        !_speech.isListening) {
      return;
    }

    // Do not allow silence/status events to terminate the microphone before
    // the mandatory six-second period.
    if (!forceStop &&
        !_minimumListeningPeriodCompleted) {
      debugPrint(
        '🎙️ Ignoring early microphone stop; minimum 6 seconds not completed.',
      );

      return;
    }

    final command =
    _voiceText.trim();

    final shouldProcess =
        processCommand &&
            command.isNotEmpty &&
            !_isProcessingCommand &&
            !_isNavigating &&
            !_micLocked;

    _isFinishingListening = true;

    try {
      // Invalidate all callbacks belonging to the current recognition
      // session before stopping the speech engine.
      ++_speechGeneration;

      await _finishListening(
        processCommand: false,
      );

      if (shouldProcess &&
          mounted &&
          !_isNavigating &&
          !_micLocked &&
          !_isProcessingCommand) {
        await _processVoiceCommand(
          command,
        );
      }
    } finally {
      _isFinishingListening = false;
    }
  }

  Future<void> _finishListening({
    required bool processCommand,
  }) async {
    _silenceTimer?.cancel();
    _maximumListeningTimer?.cancel();
    _minimumListeningTimer?.cancel();

    _minimumListeningPeriodCompleted =
    false;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        'Speech stop error: $e',
      );
    }

    _pulseController.stop();
    _pulseController.reset();

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
    });

    // Normally command processing is handled by _stopListening().
    //
    // This remains here for callers that explicitly request processing,
    // but _isFinishingListening prevents duplicate execution.
    if (processCommand &&
        !_isFinishingListening &&
        _voiceText.trim().isNotEmpty &&
        !_isProcessingCommand &&
        !_isNavigating &&
        !_micLocked) {
      await _processVoiceCommand(
        _voiceText.trim(),
      );
    }
  }

  Future<void> _safeSpeechStop() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        'Safe speech stop error: $e',
      );
    }
  }

  void _restartSilenceTimer() {
    _silenceTimer?.cancel();

    if (!_isListening) {
      return;
    }

    // Never stop the microphone during the mandatory six-second period.
    if (!_minimumListeningPeriodCompleted) {
      return;
    }

    _silenceTimer =
        Timer(
          _silenceTimeout,
              () async {
            if (!mounted ||
                !_isListening ||
                _micLocked ||
                _isNavigating ||
                _isProcessingCommand ||
                _isFinishingListening) {
              return;
            }

            await _stopListening(
              processCommand: true,
            );
          },
        );
  }

  // ===========================================================================
  // SPEECH CALLBACKS
  // ===========================================================================

  void _handleSpeechResult(
      stt.SpeechRecognitionResult result,
      ) {
    if (!mounted ||
        !_isListening ||
        _micLocked ||
        _isNavigating ||
        _isProcessingCommand ||
        _isFinishingListening) {
      return;
    }

    final recognized =
    result.recognizedWords.trim();

    if (recognized.isNotEmpty) {
      setState(() {
        _voiceText = recognized;
        _voiceError = null;
      });

      if (_minimumListeningPeriodCompleted) {
        _restartSilenceTimer();
      }
    }

    // IMPORTANT:
    //
    // speech_to_text may deliver both:
    //
    //   1. finalResult
    //   2. status = done
    //
    // for the same utterance.
    //
    // We use the guarded stop path so only one of them can process the
    // command. This prevents duplicate navigation.
    if (result.finalResult &&
        _minimumListeningPeriodCompleted) {
      _silenceTimer?.cancel();

      Future.microtask(
            () async {
          if (!mounted ||
              !_isListening ||
              _micLocked ||
              _isNavigating ||
              _isProcessingCommand ||
              _isFinishingListening) {
            return;
          }

          await _stopListening(
            processCommand: true,
          );
        },
      );
    }
  }

  void _handleSpeechStatus(
      String status,
      ) {
    debugPrint(
      'Speech status: $status',
    );

    if (!mounted ||
        _micLocked ||
        _isNavigating ||
        _isProcessingCommand ||
        _isFinishingListening) {
      return;
    }

    final normalized =
    status.toLowerCase().trim();

    if (normalized == 'done' ||
        normalized == 'not listening' ||
        normalized == 'inactive') {
      // Do not let status callbacks terminate/process the session during the
      // mandatory listening period.
      if (!_minimumListeningPeriodCompleted) {
        debugPrint(
          '🎙️ Speech status "$status" ignored during mandatory listening window.',
        );

        return;
      }

      if (!_isListening) {
        return;
      }

      _silenceTimer?.cancel();

      Future.microtask(
            () async {
          if (!mounted ||
              !_isListening ||
              _micLocked ||
              _isNavigating ||
              _isProcessingCommand ||
              _isFinishingListening) {
            return;
          }

          await _stopListening(
            processCommand: true,
          );
        },
      );
    }
  }

  void _handleSpeechError(
      dynamic error,
      ) {
    debugPrint(
      'Speech error: $error',
    );

    _silenceTimer?.cancel();
    _maximumListeningTimer?.cancel();
    _minimumListeningTimer?.cancel();

    _minimumListeningPeriodCompleted =
    false;

    // Invalidate callbacks from the failed recognition session.
    ++_speechGeneration;

    _pulseController.stop();
    _pulseController.reset();

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _voiceError =
          _friendlySpeechError(error);
    });
  }

  String _friendlySpeechError(
      dynamic error,
      ) {
    final message =
    error.toString().toLowerCase();

    if (message.contains('permission')) {
      return 'Microphone permission is required.';
    }

    if (message.contains('network')) {
      return 'Speech recognition requires a network connection.';
    }

    if (message.contains('timeout')) {
      return 'No speech was detected.';
    }

    if (message.contains('busy')) {
      return 'The microphone is currently busy.';
    }

    if (message.contains('not available')) {
      return 'Speech recognition is unavailable.';
    }

    return 'Speech recognition encountered an error.';
  }

  // ===========================================================================
  // VOICE PARSER
  // ===========================================================================

  Future<Map<String, dynamic>> interpretVoiceCommand(
      String command,
      ) async {
    String text = command
        .toLowerCase()
        .trim()
        .replaceAll(
      RegExp(r'[,!?;:]+'),
      ' ',
    )
        .replaceAll(
      RegExp(r'[-_/]+'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\s+'),
      ' ',
    )
        .trim();

    if (text.isEmpty) {
      return {
        'intent': 'unknown',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // Natural language normalization
    // -------------------------------------------------------------------------

    text = text
        .replaceAll(
      RegExp(r'\bplease\b'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\bkindly\b'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\bcan you\b'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\bcould you\b'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\bwould you\b'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\bshow me\b'),
      'show ',
    )
        .replaceAll(
      RegExp(r'\btake me to\b'),
      'open ',
    )
        .replaceAll(
      RegExp(r'\bbring me to\b'),
      'open ',
    )
        .replaceAll(
      RegExp(r'\bbring up\b'),
      'open ',
    )
        .replaceAll(
      RegExp(r'\blook for\b'),
      'find ',
    )
        .replaceAll(
      RegExp(r'\bsearch for\b'),
      'search ',
    );

    text = text
        .replaceAll(
      RegExp(r'\s+'),
      ' ',
    )
        .trim();

    // -------------------------------------------------------------------------
    // BACK
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(back|go back|go backward|previous|previous page|return|return back|back to dashboard|go to dashboard)$',
    ).hasMatch(text)) {
      return {
        'intent': 'go_back',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // PATIENT DETAILS
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(patient details|show patient details|show details|'
      r'patient information|patient info|details|'
      r'open patient details|view patient details)$',
    ).hasMatch(text)) {
      return {
        'intent': 'show_patient_details',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // ALL DOCUMENTS
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(open|show|display|view|list|get)\s+'
      r'(?:the\s+)?'
      r'(?:all\s+)?'
      r'(documents|files|patient documents|patient files)$',
    ).hasMatch(text)) {
      return {
        'intent': 'open_documents',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // NUMBERED DOCUMENTS
    // -------------------------------------------------------------------------

    final numberedDocumentMatch =
    RegExp(
      r'^(?:open|show|display|view|read)'
      r'\s+(?:the\s+)?'
      r'(?:document|file|report)'
      r'\s+'
      r'(one|two|three|four|five|six|seven|eight|nine|'
      r'first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|'
      r'1|2|3|4|5|6|7|8|9)$',
    ).firstMatch(text);

    if (numberedDocumentMatch != null) {
      final candidate =
      numberedDocumentMatch.group(1)!;

      final index =
      _spokenNumberToIndex(candidate);

      if (index != null) {
        return {
          'intent': 'open_document',
          'parameter':
          'INDEX:${index + 1}',
        };
      }
    }

    // -------------------------------------------------------------------------
    // SPECIFIC DOCUMENT
    // -------------------------------------------------------------------------

    final documentMatch =
    RegExp(
      r'^(?:open|show|display|view|read)'
      r'\s+(?:the\s+)?'
      r'(?:document|file|report)'
      r'(?:\s+(.+))?$',
    ).firstMatch(text);

    if (documentMatch != null) {
      final parameter =
      documentMatch.group(1)?.trim();

      return {
        'intent': 'open_document',
        'parameter':
        parameter?.isEmpty == true
            ? null
            : parameter,
      };
    }

    // -------------------------------------------------------------------------
    // PATIENT COMMANDS
    // -------------------------------------------------------------------------

    final patientCommandMatch =
    RegExp(
      r'^(find|search|open|show|display|view|get|fetch|select)'
      r'(?:\s+(?:the\s+)?)?'
      r'(?:patient\s*)?'
      r'(?:number\s*)?'
      r'(.+)$',
    ).firstMatch(text);

    if (patientCommandMatch != null) {
      String parameter =
          patientCommandMatch.group(2)?.trim() ??
              '';

      parameter = parameter
          .replaceFirst(
        RegExp(
          r'\s+(please|thanks|thank you)$',
        ),
        '',
      )
          .trim();

      if (parameter.isNotEmpty) {
        return {
          'intent': 'find_patient',
          'parameter':
          _normalizePatientIdentifier(
            parameter,
          ),
        };
      }
    }

    // -------------------------------------------------------------------------
    // DIRECT PATIENT IDENTIFIER
    // -------------------------------------------------------------------------

    final directPatient =
    _normalizePatientIdentifier(text);

    if (_looksLikePatientId(
      directPatient,
    )) {
      return {
        'intent': 'find_patient',
        'parameter': directPatient,
      };
    }

    return {
      'intent': 'unknown',
      'parameter': null,
    };
  }

  String _normalizePatientIdentifier(
      String value,
      ) {
    String parameter = value
        .toLowerCase()
        .trim()
        .replaceAll(
      RegExp(r'[,!?;:]+'),
      ' ',
    )
        .replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (parameter.isEmpty) {
      return '';
    }

    parameter = parameter.replaceFirst(
      RegExp(
        r'^(the\s+)?patient\s+',
      ),
      '',
    );

    parameter = parameter.replaceFirst(
      RegExp(
        r'^number\s+',
      ),
      '',
    );

    parameter = parameter.replaceFirst(
      RegExp(
        r'^(pee|pea)\s*',
      ),
      'p ',
    );

    parameter = parameter.trim();

    const Map<String, String>
    numberWords = {
      'zero': '0',
      'one': '1',
      'won': '1',
      'two': '2',
      'to': '2',
      'too': '2',
      'three': '3',
      'four': '4',
      'for': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'ate': '8',
      'nine': '9',
    };

    final spokenNumber =
    RegExp(
      r'^(zero|one|won|two|to|too|three|four|for|'
      r'five|six|seven|eight|ate|nine)$',
    ).firstMatch(parameter);

    if (spokenNumber != null) {
      final digit =
      numberWords[
      spokenNumber.group(1)!]!;

      return 'P ${digit.padLeft(3, '0')}';
    }

    final spokenPNumber =
    RegExp(
      r'^p\s+'
      r'(zero|one|won|two|to|too|three|four|for|'
      r'five|six|seven|eight|ate|nine)$',
    ).firstMatch(parameter);

    if (spokenPNumber != null) {
      final digit =
      numberWords[
      spokenPNumber.group(1)!]!;

      return 'P ${digit.padLeft(3, '0')}';
    }

    final pId =
    RegExp(
      r'^p\s*([0-9]{1,3})$',
      caseSensitive: false,
    ).firstMatch(parameter);

    if (pId != null) {
      final digits =
      pId.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    final numericId =
    RegExp(
      r'^([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (numericId != null) {
      final digits =
      numericId.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    return parameter;
  }

  bool _looksLikePatientId(
      String value,
      ) {
    return RegExp(
      r'^p\s*[0-9]{1,3}$',
      caseSensitive: false,
    ).hasMatch(
      value.trim(),
    );
  }

  int? _spokenNumberToIndex(
      String value,
      ) {
    switch (value.toLowerCase()) {
      case 'one':
      case 'first':
      case '1':
        return 0;

      case 'two':
      case 'second':
      case '2':
        return 1;

      case 'three':
      case 'third':
      case '3':
        return 2;

      case 'four':
      case 'fourth':
      case '4':
        return 3;

      case 'five':
      case 'fifth':
      case '5':
        return 4;

      case 'six':
      case 'sixth':
      case '6':
        return 5;

      case 'seven':
      case 'seventh':
      case '7':
        return 6;

      case 'eight':
      case 'eighth':
      case '8':
        return 7;

      case 'nine':
      case 'ninth':
      case '9':
        return 8;
    }

    return null;
  }

  // ===========================================================================
  // COMMAND PROCESSING
  // ===========================================================================

  Future<void> _processVoiceCommand(
      String command,
      ) async {
    if (_isProcessingCommand ||
        _isNavigating ||
        _micLocked ||
        !mounted ||
        command.trim().isEmpty) {
      return;
    }

    // Set this before any await so another speech callback cannot enter.
    _isProcessingCommand = true;

    // Invalidate all recognition callbacks that are still queued.
    ++_speechGeneration;

    try {
      // Stop recognition completely before executing a command.
      await _hardStopMic();

      if (!mounted ||
          _isNavigating ||
          _micLocked) {
        return;
      }

      setState(() {
        _voiceError = null;
      });

      final result =
      await interpretVoiceCommand(
        command,
      );

      if (!mounted ||
          _isNavigating ||
          _micLocked) {
        return;
      }

      final intent =
      result['intent'];

      final parameter =
      result['parameter']?.toString();

      debugPrint(
        'Voice command: $command',
      );

      debugPrint(
        'Parsed intent: $intent',
      );

      debugPrint(
        'Parsed parameter: $parameter',
      );

      switch (intent) {
        case 'go_back':
          await _goBackToSurgeonDashboard();
          break;

        case 'show_patient_details':
          await _scrollToTop();
          break;

        case 'open_documents':
          await _scrollToDocuments();
          break;

        case 'open_document':
          await _handleDocumentCommand(
            parameter,
          );
          break;

        case 'find_patient':
          await _showVoiceMessage(
            'Patient search is available from the surgeon dashboard.',
          );
          break;

        default:
          await _showVoiceMessage(
            'Command not recognized.',
          );
      }
    } catch (e) {
      debugPrint(
        'Voice command processing error: $e',
      );

      if (mounted &&
          !_isNavigating) {
        setState(() {
          _voiceError =
          'Unable to process the voice command.';
        });
      }
    } finally {
      _isProcessingCommand = false;
    }
  }

  Future<void> _handleDocumentCommand(
      String? parameter,
      ) async {
    if (_documents.isEmpty) {
      await _showVoiceMessage(
        'There are no uploaded documents.',
      );

      return;
    }

    if (parameter == null ||
        parameter.trim().isEmpty) {
      await _scrollToDocuments();

      return;
    }

    final normalized =
    parameter.toLowerCase().trim();

    // -------------------------------------------------------------------------
    // Document index
    // -------------------------------------------------------------------------

    if (normalized.startsWith('index:')) {
      final index =
      int.tryParse(
        normalized.replaceFirst(
          'index:',
          '',
        ),
      );

      if (index != null) {
        final zeroBased =
            index - 1;

        if (zeroBased >= 0 &&
            zeroBased < _documents.length) {
          await _openDocumentByIndex(
            zeroBased,
          );

          return;
        }
      }
    }

    // -------------------------------------------------------------------------
    // Filename search
    // -------------------------------------------------------------------------

    for (
    int i = 0;
    i < _documents.length;
    i++
    ) {
      final doc =
      _documents[i];

      if (doc is! Map) {
        continue;
      }

      final fileName =
      (doc['fileName'] ?? '')
          .toString()
          .toLowerCase();

      final fileUrl =
      (doc['fileUrl'] ?? '')
          .toString()
          .toLowerCase();

      if (fileName.contains(normalized) ||
          fileUrl.contains(normalized)) {
        await _openDocumentByIndex(i);

        return;
      }
    }

    await _scrollToDocuments();

    if (mounted) {
      setState(() {
        _voiceError =
        'No matching document was found.';
      });
    }
  }

  // ===========================================================================
  // DOCUMENT NAVIGATION
  // ===========================================================================

  Future<void> _openDocumentByIndex(
      int index,
      ) async {
    if (index < 0 ||
        index >= _documents.length ||
        _isNavigating ||
        _micLocked) {
      return;
    }

    final document =
    _documents[index];

    if (document is! Map) {
      return;
    }

    final resolvedUrl =
    await _resolveSupabaseDocumentUrl(
      document,
    );

    if (!mounted ||
        resolvedUrl == null ||
        resolvedUrl.trim().isEmpty ||
        _isNavigating) {
      return;
    }

    final fileType =
    document['fileType']?.toString();

    final fileName =
    document['fileName']?.toString();

    await _openDocument(
      context,
      resolvedUrl,
      fileType: fileType,
      fileName: fileName,
    );
  }

  Future<String?> _resolveSupabaseDocumentUrl(
      Map document,
      ) async {
    final provider =
    document['storageProvider']
        ?.toString()
        .trim()
        .toLowerCase();

    final bucket =
    document['bucket']
        ?.toString()
        .trim();

    final storagePath =
    document['storagePath']
        ?.toString()
        .trim();

    if (provider == 'supabase' &&
        bucket != null &&
        bucket.isNotEmpty &&
        storagePath != null &&
        storagePath.isNotEmpty) {
      try {
        final supabaseStorage =
            Supabase.instance.client.storage;

        final publicUrl =
        supabaseStorage
            .from(bucket)
            .getPublicUrl(
          storagePath,
        );

        if (publicUrl.trim().isNotEmpty) {
          return publicUrl;
        }
      } catch (e) {
        debugPrint(
          'Supabase public URL resolution failed: $e',
        );
      }
    }

    final storedUrl =
    document['fileUrl']
        ?.toString()
        .trim();

    if (storedUrl != null &&
        storedUrl.isNotEmpty) {
      return storedUrl;
    }

    return null;
  }

  Future<void> _openDocument(
      BuildContext context,
      String? url, {
        String? fileType,
        String? fileName,
      }) async {
    if (!mounted ||
        url == null ||
        url.trim().isEmpty ||
        _isNavigating) {
      return;
    }

    // -------------------------------------------------------------------------
    // LOCK NAVIGATION AND MICROPHONE FIRST
    // -------------------------------------------------------------------------

    _isNavigating = true;

    _micLocked = true;
    _micPermanentlyDisabled = true;

    // Invalidate all pending speech callbacks immediately.
    ++_speechGeneration;

    debugPrint(
      '📂 Document opening requested. Shutting microphone down.',
    );

    await _hardStopMic();

    if (!mounted) {
      return;
    }

    final normalizedType =
    (fileType ?? '')
        .trim()
        .toLowerCase();

    final normalizedName =
    (fileName ?? '')
        .trim()
        .toLowerCase();

    final isPdf =
        normalizedType == 'pdf' ||
            normalizedName.endsWith('.pdf') ||
            _urlPathHasExtension(
              url,
              'pdf',
            );

    final isImage =
    _isImageDocument(
      normalizedType,
      normalizedName,
      url,
    );

    try {
      if (isPdf) {
        // PDF replaces this page. There is no reason for this page to remain
        // active underneath the PDF viewer.
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PDFViewerPage(
                  pdfUrl: url,
                ),
          ),
        );
      } else if (isImage) {
        final imageDocuments =
        _documents.where(
              (document) {
            if (document is! Map) {
              return false;
            }

            final currentType =
            (document['fileType'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

            final currentName =
            (document['fileName'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

            final currentUrl =
            (document['fileUrl'] ?? '')
                .toString()
                .trim();

            return _isImageDocument(
              currentType,
              currentName,
              currentUrl,
            );
          },
        ).toList();

        final imageUrls =
        <String>[];

        for (
        final document
        in imageDocuments
        ) {
          if (document is! Map) {
            continue;
          }

          final imageUrl =
          await _resolveSupabaseDocumentUrl(
            document,
          );

          if (imageUrl != null &&
              imageUrl.trim().isNotEmpty) {
            imageUrls.add(imageUrl);
          }
        }

        if (imageUrls.isEmpty) {
          await _showVoiceMessage(
            'The image could not be loaded from Supabase Storage.',
          );

          return;
        }

        final initialIndex =
        imageUrls.indexOf(url);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ImageViewerPage(
                  imageUrls:
                  imageUrls,
                  initialIndex:
                  initialIndex >= 0
                      ? initialIndex
                      : 0,
                ),
          ),
        );
      } else {
        await _downloadAndOpenFile(
          url,
          fileName: fileName,
        );
      }
    } catch (e) {
      debugPrint(
        'Document opening error: $e',
      );

      if (mounted) {
        await _showVoiceMessage(
          'Unable to open the selected document.',
        );
      }
    }

    // IMPORTANT:
    //
    // Do not unlock the microphone here.
    //
    // Once a document workflow has started, this PatientHistoryPage must
    // never automatically start listening again.
  }

  bool _isImageDocument(
      String fileType,
      String fileName,
      String url,
      ) {
    const imageTypes =
    <String>{
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'bmp',
      'heic',
      'heif',
    };

    if (imageTypes.contains(fileType)) {
      return true;
    }

    final candidates =
    <String>[
      fileName,
      url.split('?').first.toLowerCase(),
    ];

    for (final candidate
    in candidates) {
      for (final extension
      in imageTypes) {
        if (candidate.endsWith(
          '.$extension',
        )) {
          return true;
        }
      }
    }

    return false;
  }

  bool _urlPathHasExtension(
      String url,
      String extension,
      ) {
    try {
      final uri =
      Uri.parse(url);

      final path =
      uri.path.toLowerCase();

      return path.endsWith(
        '.$extension',
      );
    } catch (_) {
      return url
          .toLowerCase()
          .split('?')
          .first
          .endsWith(
        '.$extension',
      );
    }
  }

  Future<void> _downloadAndOpenFile(
      String url, {
        String? fileName,
      }) async {
    if (!mounted) {
      return;
    }

    try {
      final response =
      await http.get(
        Uri.parse(url),
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw HttpException(
          'Supabase Storage returned HTTP ${response.statusCode}.',
        );
      }

      final directory =
      await getTemporaryDirectory();

      final safeName =
      _safeLocalFileName(
        fileName ??
            _fileNameFromUrl(url),
      );

      final file = File(
        '${directory.path}${Platform.pathSeparator}$safeName',
      );

      await file.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      final result =
      await OpenFile.open(
        file.path,
      );

      debugPrint(
        'Open file result: ${result.type} - ${result.message}',
      );

      if (result.type !=
          ResultType.done &&
          mounted) {
        await _showVoiceMessage(
          result.message.isNotEmpty
              ? result.message
              : 'No application is available to open this file.',
        );
      }
    } catch (e) {
      debugPrint(
        'Supabase file download/open error: $e',
      );

      if (mounted) {
        await _showVoiceMessage(
          'Unable to download the file from Supabase Storage.',
        );
      }
    }
  }

  String _fileNameFromUrl(
      String url,
      ) {
    try {
      final uri =
      Uri.parse(url);

      if (uri.pathSegments
          .isNotEmpty) {
        return Uri.decodeComponent(
          uri.pathSegments.last,
        );
      }
    } catch (_) {}

    return 'clinical_document';
  }

  String _safeLocalFileName(
      String value,
      ) {
    var name =
    value.trim();

    if (name.isEmpty) {
      name =
      'clinical_document';
    }

    name = name.replaceAll(
      RegExp(
        r'[<>:"/\\|?*]',
      ),
      '_',
    );

    return name;
  }

  // ===========================================================================
  // HARD MICROPHONE SHUTDOWN
  // ===========================================================================

  Future<void> _hardStopMic() async {
    // Invalidate pending recognition callbacks before stopping the engine.
    ++_speechGeneration;

    _isStartingMicrophone = false;

    _silenceTimer?.cancel();
    _maximumListeningTimer?.cancel();
    _minimumListeningTimer?.cancel();

    _minimumListeningPeriodCompleted =
    false;

    _isListening = false;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        'Hard microphone stop error: $e',
      );
    }

    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint(
        'Speech cancel error: $e',
      );
    }

    _pulseController.stop();
    _pulseController.reset();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }

    debugPrint(
      '⛔ Microphone fully stopped.',
    );
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  Future<void> _goBackToSurgeonDashboard() async {
    if (_isNavigating) {
      return;
    }

    // -------------------------------------------------------------------------
    // LOCK EVERYTHING BEFORE THE FIRST AWAIT
    // -------------------------------------------------------------------------

    _isNavigating = true;

    _micLocked = true;
    _micPermanentlyDisabled = true;

    // Invalidate every recognition callback currently in flight.
    ++_speechGeneration;

    debugPrint(
      '⬅️ Returning to existing SurgeonDashboard.',
    );

    await _hardStopMic();

    if (!mounted) {
      return;
    }

    // -------------------------------------------------------------------------
    // CRITICAL FIX
    //
    // PatientHistoryPage was opened ON TOP OF SurgeonDashboard.
    //
    // Therefore, the correct action is simply:
    //
    //     Navigator.pop()
    //
    // NOT:
    //
    //     Navigator.pushAndRemoveUntil(
    //       SurgeonDashboard(),
    //     )
    //
    // Creating another dashboard creates another speech-recognition lifecycle
    // and is one of the primary causes of the feedback/navigation loop.
    // -------------------------------------------------------------------------

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // -------------------------------------------------------------------------
    // DEFENSIVE FALLBACK
    //
    // This branch should normally never execute because the surgeon dashboard
    // should already be below this page.
    // -------------------------------------------------------------------------

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
        const SurgeonDashboard(),
      ),
    );
  }

  // ===========================================================================
  // SCROLL
  // ===========================================================================

  Future<void> _scrollToDocuments() async {
    if (!mounted) {
      return;
    }

    final target =
        _documentsKey.currentContext;

    if (target == null) {
      return;
    }

    await Scrollable.ensureVisible(
      target,
      duration:
      const Duration(
        milliseconds: 650,
      ),
      curve:
      Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController
        .hasClients) {
      return;
    }

    await _scrollController.animateTo(
      0,
      duration:
      const Duration(
        milliseconds: 600,
      ),
      curve:
      Curves.easeOutCubic,
    );
  }

  // ===========================================================================
  // DOCUMENT EXTRACTION
  // ===========================================================================

  List<dynamic> _extractDocuments() {
    final raw =
    widget.patientData['documents'];

    if (raw is! List) {
      return <dynamic>[];
    }

    return List<dynamic>.from(raw);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _stringValue(
      dynamic value, {
        String fallback = 'N/A',
      }) {
    if (value == null) {
      return fallback;
    }

    final stringValue =
    value.toString().trim();

    return stringValue.isEmpty
        ? fallback
        : stringValue;
  }

  String _patientInitials() {
    final name =
    _stringValue(
      widget.patientData['name'],
      fallback: 'Patient',
    );

    final parts = name
        .trim()
        .split(
      RegExp(r'\s+'),
    )
        .where(
          (part) =>
      part.isNotEmpty,
    )
        .toList();

    if (parts.isEmpty) {
      return 'PT';
    }

    if (parts.length == 1) {
      final value =
          parts.first;

      return value
          .substring(
        0,
        value.length >= 2
            ? 2
            : 1,
      )
          .toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'
        .toUpperCase();
  }

  String _documentName(
      dynamic document,
      ) {
    if (document is! Map) {
      return 'Unknown document';
    }

    final fileName =
    document['fileName'];

    if (fileName != null &&
        fileName
            .toString()
            .trim()
            .isNotEmpty) {
      return fileName.toString();
    }

    final url =
    document['fileUrl']
        ?.toString();

    if (url == null ||
        url.isEmpty) {
      return 'Unknown document';
    }

    try {
      final uri =
      Uri.parse(url);

      if (uri.pathSegments
          .isNotEmpty) {
        return Uri.decodeComponent(
          uri.pathSegments.last,
        );
      }
    } catch (_) {}

    return 'Clinical document';
  }

  String _documentType(
      dynamic document,
      ) {
    if (document is! Map) {
      return 'FILE';
    }

    final type =
    document['fileType']
        ?.toString()
        .trim();

    if (type != null &&
        type.isNotEmpty) {
      return type.toUpperCase();
    }

    final name =
    _documentName(
      document,
    );

    final dot =
    name.lastIndexOf('.');

    if (dot != -1 &&
        dot < name.length - 1) {
      return name
          .substring(dot + 1)
          .toUpperCase();
    }

    return 'FILE';
  }

  IconData _documentIcon(
      dynamic document,
      ) {
    final type =
    _documentType(
      document,
    ).toLowerCase();

    switch (type) {
      case 'pdf':
        return Icons
            .picture_as_pdf_rounded;

      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return Icons
            .image_rounded;

      case 'doc':
      case 'docx':
        return Icons
            .description_rounded;

      case 'xls':
      case 'xlsx':
        return Icons
            .table_chart_rounded;

      default:
        return Icons
            .insert_drive_file_rounded;
    }
  }

  Future<void> _showVoiceMessage(
      String message,
      ) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _voiceError = message;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        behavior:
        SnackBarBehavior.floating,
        backgroundColor:
        _cardSecondary,
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
        ),
        content: Row(
          children: [
            const Icon(
              Icons
                  .mic_none_rounded,
              color: _cyan,
              size: 20,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                message,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return AnnotatedRegion<
        SystemUiOverlayStyle>(
      value:
      const SystemUiOverlayStyle(
        statusBarColor:
        _background,
        statusBarIconBrightness:
        Brightness.light,
        systemNavigationBarColor:
        _background,
        systemNavigationBarIconBrightness:
        Brightness.light,
      ),
      child: WillPopScope(
        onWillPop: () async {
          await _goBackToSurgeonDashboard();

          return false;
        },
        child: Scaffold(
          backgroundColor:
          _background,
          body: SafeArea(
            child: FadeTransition(
              opacity: _pageFade,
              child:
              CustomScrollView(
                controller:
                _scrollController,
                physics:
                const BouncingScrollPhysics(
                  parent:
                  AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child:
                    _buildTopBar(),
                  ),

                  SliverToBoxAdapter(
                    child:
                    SlideTransition(
                      position:
                      _heroSlide,
                      child:
                      FadeTransition(
                        opacity:
                        _heroFade,
                        child:
                        _buildHeroCard(),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child:
                    _buildVoiceStatus(),
                  ),

                  // KPI CARDS REMOVED.

                  SliverToBoxAdapter(
                    child:
                    _buildPatientInformation(),
                  ),

                  SliverToBoxAdapter(
                    child:
                    _buildClinicalAssignment(),
                  ),

                  SliverToBoxAdapter(
                    child: Container(
                      key:
                      _documentsKey,
                      child:
                      _buildDocumentsSection(),
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child:
                    SizedBox(
                      height: 34,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP BAR
  // ===========================================================================

  Widget _buildTopBar() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12,
      ),
      child: Row(
        children: [
          _buildIconButton(
            icon:
            Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed:
            _goBackToSurgeonDashboard,
          ),

          const SizedBox(
            width: 13,
          ),

          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  'CLINICAL RECORD',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                SizedBox(
                  height: 3,
                ),
                Text(
                  'Patient History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          _buildIconButton(
            icon:
            Icons.keyboard_voice_rounded,
            tooltip:
            'Voice command',
            onPressed:
            _isProcessingCommand ||
                _isStartingMicrophone ||
                _isNavigating ||
                _micLocked
                ? null
                : _toggleMicrophone,
            active:
            _isListening,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? _danger
            : _cardSecondary,
        borderRadius:
        BorderRadius.circular(
          13,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius:
          BorderRadius.circular(
            13,
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: onPressed == null
                  ? Colors.white24
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HERO
  // ===========================================================================

  Widget _buildHeroCard() {
    final name =
    _stringValue(
      widget.patientData['name'],
      fallback:
      'Unknown Patient',
    );

    final patientId =
    _stringValue(
      widget.patientData[
      'patientId'],
      fallback:
      widget.patientId,
    );

    final age =
    _stringValue(
      widget.patientData['age'],
    );

    final gender =
    _stringValue(
      widget.patientData['gender'],
    );

    return Container(
      margin:
      const EdgeInsets.fromLTRB(
        18,
        4,
        18,
        14,
      ),
      padding:
      const EdgeInsets.all(
        20,
      ),
      decoration:
      BoxDecoration(
        gradient:
        const LinearGradient(
          colors: [
            _navyBlue,
            Color(0xFF0A2A40),
          ],
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color:
          _cyan.withOpacity(
            0.14,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black
                .withOpacity(
              0.25,
            ),
            blurRadius: 30,
            offset:
            const Offset(
              0,
              14,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration:
                BoxDecoration(
                  shape:
                  BoxShape.circle,
                  color: _teal
                      .withOpacity(
                    0.20,
                  ),
                  border: Border.all(
                    color: _cyan
                        .withOpacity(
                      0.35,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    _patientInitials(),
                    style:
                    const TextStyle(
                      color:
                      Colors.white,
                      fontSize: 19,
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                width: 14,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        color:
                        Colors.white,
                        fontSize: 24,
                        height: 1.15,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 7,
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons
                              .badge_outlined,
                          size: 15,
                          color:
                          _mutedText,
                        ),
                        const SizedBox(
                          width: 6,
                        ),
                        Flexible(
                          child: Text(
                            patientId,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            const TextStyle(
                              color:
                              _secondaryText,
                              fontSize:
                              13,
                              fontWeight:
                              FontWeight
                                  .w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
                decoration:
                BoxDecoration(
                  color: _success
                      .withOpacity(
                    0.10,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    9,
                  ),
                  border: Border.all(
                    color: _success
                        .withOpacity(
                      0.20,
                    ),
                  ),
                ),
                child:
                const Row(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Icon(
                      Icons
                          .check_circle_rounded,
                      size: 12,
                      color:
                      _success,
                    ),
                    SizedBox(
                      width: 5,
                    ),
                    Text(
                      'ACTIVE',
                      style:
                      TextStyle(
                        color:
                        _success,
                        fontSize: 9,
                        fontWeight:
                        FontWeight.w800,
                        letterSpacing:
                        0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 21,
          ),
          Container(
            height: 1,
            color:
            Colors.white
                .withOpacity(
              0.07,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child:
                _buildHeroMetric(
                  Icons
                      .calendar_month_outlined,
                  'Age',
                  age,
                ),
              ),
              _buildHeroDivider(),
              Expanded(
                child:
                _buildHeroMetric(
                  Icons.wc_rounded,
                  'Gender',
                  gender,
                ),
              ),
              _buildHeroDivider(),
              Expanded(
                child:
                _buildHeroMetric(
                  Icons
                      .folder_copy_outlined,
                  'Documents',
                  _documents.length
                      .toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric(
      IconData icon,
      String label,
      String value,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: _cyan,
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              Text(
                label,
                style:
                const TextStyle(
                  color:
                  _mutedText,
                  fontSize: 10,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
              const SizedBox(
                height: 2,
              ),
              Text(
                value,
                maxLines: 1,
                overflow:
                TextOverflow
                    .ellipsis,
                style:
                const TextStyle(
                  color:
                  Colors.white,
                  fontSize: 13,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroDivider() {
    return Container(
      width: 1,
      height: 30,
      margin:
      const EdgeInsets.symmetric(
        horizontal: 7,
      ),
      color:
      Colors.white.withOpacity(
        0.08,
      ),
    );
  }

  // ===========================================================================
  // VOICE STATUS
  // ===========================================================================

  Widget _buildVoiceStatus() {
    if (!_isListening &&
        _voiceText.isEmpty &&
        _voiceError == null) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration:
      const Duration(
        milliseconds: 250,
      ),
      margin:
      const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        14,
      ),
      padding:
      const EdgeInsets.all(
        13,
      ),
      decoration:
      BoxDecoration(
        color: _isListening
            ? _teal.withOpacity(
          0.10,
        )
            : _card,
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color: _isListening
              ? _cyan.withOpacity(
            0.20,
          )
              : Colors.white
              .withOpacity(
            0.06,
          ),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _micPulse,
            builder:
                (context, child) {
              return Transform.scale(
                scale: _isListening
                    ? _micPulse.value
                    : 1.0,
                child: child,
              );
            },
            child: Container(
              width: 36,
              height: 36,
              decoration:
              BoxDecoration(
                shape:
                BoxShape.circle,
                color: _isListening
                    ? _danger.withOpacity(
                  0.14,
                )
                    : _navyBlue,
              ),
              child: Icon(
                _isListening
                    ? Icons.mic_rounded
                    : Icons
                    .mic_none_rounded,
                size: 18,
                color: _isListening
                    ? _danger
                    : _cyan,
              ),
            ),
          ),
          const SizedBox(
            width: 11,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  _isListening
                      ? 'Listening for command'
                      : 'Voice command',
                  style:
                  const TextStyle(
                    color:
                    Colors.white,
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  _voiceError ??
                      (_voiceText.isEmpty
                          ? 'Say “open document one” or “go back”.'
                          : _voiceText),
                  maxLines: 2,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style: TextStyle(
                    color:
                    _voiceError !=
                        null
                        ? const Color(
                      0xFFFF8A8A,
                    )
                        : _mutedText,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PATIENT INFORMATION
  // ===========================================================================

  Widget _buildPatientInformation() {
    return _buildSection(
      icon:
      Icons.person_outline_rounded,
      title:
      'Patient Information',
      subtitle:
      'Personal and contact details',
      child: Column(
        children: [
          _buildInformationRow(
            Icons.badge_outlined,
            'Patient ID',
            _stringValue(
              widget.patientData[
              'patientId'],
              fallback:
              widget.patientId,
            ),
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            Icons.phone_outlined,
            'Phone',
            _stringValue(
              widget.patientData[
              'phone'],
            ),
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            Icons.email_outlined,
            'Email',
            _stringValue(
              widget.patientData[
              'email'],
            ),
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            Icons.cake_outlined,
            'Age',
            _stringValue(
              widget.patientData[
              'age'],
            ),
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            Icons.wc_rounded,
            'Gender',
            _stringValue(
              widget.patientData[
              'gender'],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationRow(
      IconData icon,
      String label,
      String value,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 11,
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration:
            BoxDecoration(
              color: _navyBlue
                  .withOpacity(
                0.65,
              ),
              borderRadius:
              BorderRadius.circular(
                11,
              ),
            ),
            child: Icon(
              icon,
              size: 17,
              color: _cyan,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Text(
              label,
              style:
              const TextStyle(
                color:
                _mutedText,
                fontSize: 12,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign:
              TextAlign.right,
              maxLines: 3,
              overflow:
              TextOverflow
                  .ellipsis,
              style:
              const TextStyle(
                color:
                Colors.white,
                fontSize: 13,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationDivider() {
    return Container(
      height: 1,
      color:
      Colors.white.withOpacity(
        0.045,
      ),
    );
  }

  // ===========================================================================
  // CLINICAL ASSIGNMENT
  // ===========================================================================

  Widget _buildClinicalAssignment() {
    final doctor =
        _assignedDoctorName;

    return _buildSection(
      icon:
      Icons.medical_services_outlined,
      title:
      'Clinical Assignment',
      subtitle:
      'Current care responsibility',
      child: Container(
        padding:
        const EdgeInsets.all(
          14,
        ),
        decoration:
        BoxDecoration(
          color:
          _cardSecondary,
          borderRadius:
          BorderRadius.circular(
            15,
          ),
          border: Border.all(
            color:
            _cyan.withOpacity(
              0.10,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration:
              BoxDecoration(
                shape:
                BoxShape.circle,
                color: _teal
                    .withOpacity(
                  0.18,
                ),
              ),
              child:
              const Icon(
                Icons
                    .medical_services_rounded,
                color: _cyan,
                size: 21,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  const Text(
                    'Assigned Doctor',
                    style:
                    TextStyle(
                      color:
                      _mutedText,
                      fontSize: 10,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    doctor,
                    maxLines: 2,
                    overflow:
                    TextOverflow
                        .ellipsis,
                    style:
                    const TextStyle(
                      color:
                      Colors.white,
                      fontSize: 14,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration:
              BoxDecoration(
                color: _cyan
                    .withOpacity(
                  0.07,
                ),
                borderRadius:
                BorderRadius.circular(
                  8,
                ),
              ),
              child:
              const Icon(
                Icons
                    .check_circle_outline_rounded,
                color: _cyan,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DOCUMENTS
  // ===========================================================================

  Widget _buildDocumentsSection() {
    return _buildSection(
      icon:
      Icons.folder_open_rounded,
      title:
      'Uploaded Documents',
      subtitle:
      _documents.isEmpty
          ? 'No clinical files available'
          : '${_documents.length} document${_documents.length == 1 ? '' : 's'} attached',
      child: _documents.isEmpty
          ? _buildEmptyDocuments()
          : Column(
        children:
        List.generate(
          _documents.length,
              (index) {
            return Padding(
              padding:
              EdgeInsets.only(
                bottom:
                index ==
                    _documents.length -
                        1
                    ? 0
                    : 9,
              ),
              child:
              _buildDocumentCard(
                _documents[index],
                index,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDocumentCard(
      dynamic document,
      int index,
      ) {
    final name =
    _documentName(
      document,
    );

    final type =
    _documentType(
      document,
    );

    return Material(
      color: _card,
      borderRadius:
      BorderRadius.circular(
        15,
      ),
      child: InkWell(
        onTap: () {
          if (_isNavigating ||
              _micLocked) {
            return;
          }

          _openDocumentByIndex(
            index,
          );
        },
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        child: Container(
          padding:
          const EdgeInsets.all(
            12,
          ),
          decoration:
          BoxDecoration(
            borderRadius:
            BorderRadius.circular(
              15,
            ),
            border: Border.all(
              color: Colors.white
                  .withOpacity(
                0.055,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration:
                BoxDecoration(
                  color:
                  _navyBlue,
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  _documentIcon(
                    document,
                  ),
                  color: _cyan,
                  size: 21,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        color:
                        Colors.white,
                        fontSize: 12.5,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Row(
                      children: [
                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration:
                          BoxDecoration(
                            color: _cyan
                                .withOpacity(
                              0.07,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              5,
                            ),
                          ),
                          child:
                          Text(
                            type,
                            style:
                            const TextStyle(
                              color:
                              _cyan,
                              fontSize:
                              8.5,
                              fontWeight:
                              FontWeight
                                  .w800,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 7,
                        ),
                        Text(
                          'Document ${index + 1}',
                          style:
                          const TextStyle(
                            color:
                            _mutedText,
                            fontSize:
                            9.5,
                            fontWeight:
                            FontWeight
                                .w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Container(
                width: 35,
                height: 35,
                decoration:
                BoxDecoration(
                  color:
                  _navyBlue,
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
                ),
                child:
                const Icon(
                  Icons
                      .open_in_new_rounded,
                  color:
                  _secondaryText,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDocuments() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        vertical: 27,
        horizontal: 20,
      ),
      decoration:
      BoxDecoration(
        color: _card,
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.05,
          ),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons
                .folder_off_outlined,
            size: 34,
            color:
            Color(0xFF617A89),
          ),
          SizedBox(
            height: 9,
          ),
          Text(
            'No documents uploaded',
            style:
            TextStyle(
              color:
              Colors.white,
              fontSize: 13,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          SizedBox(
            height: 5,
          ),
          Text(
            'Clinical reports and imaging files will appear here.',
            textAlign:
            TextAlign.center,
            style:
            TextStyle(
              color:
              _mutedText,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION
  // ===========================================================================

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin:
      const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        17,
      ),
      padding:
      const EdgeInsets.all(
        16,
      ),
      decoration:
      BoxDecoration(
        color: const Color(
          0xFF091D2B,
        ),
        borderRadius:
        BorderRadius.circular(
          19,
        ),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.05,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration:
                BoxDecoration(
                  color: _teal
                      .withOpacity(
                    0.12,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    10,
                  ),
                ),
                child: Icon(
                  icon,
                  color: _cyan,
                  size: 17,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      title,
                      style:
                      const TextStyle(
                        color:
                        Colors.white,
                        fontSize: 15,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        color:
                        _mutedText,
                        fontSize: 9.5,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          child,
        ],
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    // Invalidate every pending async speech callback.
    ++_speechGeneration;

    // Lock before disposing the speech engine.
    _micLocked = true;
    _micPermanentlyDisabled =
    true;

    _initializationTimer?.cancel();
    _silenceTimer?.cancel();
    _maximumListeningTimer?.cancel();
    _minimumListeningTimer?.cancel();

    try {
      _speech.stop();
      _speech.cancel();
    } catch (_) {}

    _scrollController.dispose();

    _pageController.dispose();
    _heroController.dispose();
    _pulseController.dispose();

    super.dispose();
  }
}