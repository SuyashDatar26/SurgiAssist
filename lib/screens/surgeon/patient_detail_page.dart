import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

class PatientDetailPage extends StatefulWidget {
  final String patientId;

  const PatientDetailPage({
    Key? key,
    required this.patientId,
  }) : super(key: key);

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // FIRESTORE
  // ---------------------------------------------------------------------------

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _patientData;
  String? _doctorName;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // VOICE ASSISTANT
  // ---------------------------------------------------------------------------

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechInitialized = false;
  bool _isListening = false;
  bool _isProcessingCommand = false;

  String _voiceText = '';
  String? _voiceError;

  Timer? _silenceTimer;

  // How long the system waits after the last recognized words.
  static const Duration _silenceTimeout = Duration(seconds: 2);

  // ---------------------------------------------------------------------------
  // ANIMATIONS
  // ---------------------------------------------------------------------------

  late AnimationController _pageAnimationController;
  late AnimationController _headerAnimationController;
  late AnimationController _pulseAnimationController;

  late Animation<double> _pageFadeAnimation;
  late Animation<Offset> _headerSlideAnimation;
  late Animation<double> _headerFadeAnimation;
  late Animation<double> _pulseAnimation;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _initializeAnimations();
    _initializeTts();
    _loadPatient();
  }

  void _initializeAnimations() {
    _pageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _headerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pageFadeAnimation = CurvedAnimation(
      parent: _pageAnimationController,
      curve: Curves.easeOutCubic,
    );

    _headerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _headerFadeAnimation = CurvedAnimation(
      parent: _headerAnimationController,
      curve: Curves.easeOut,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pageAnimationController.forward();

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) {
        _headerAnimationController.forward();
      }
    });
  }

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(0.85);
    } catch (_) {
      // TTS is an enhancement and should never prevent the page from working.
    }
  }

  @override
  void dispose() {
    _stopListening(
      speakConfirmation: false,
      clearText: false,
    );

    _silenceTimer?.cancel();

    _tts.stop();

    _pageAnimationController.dispose();
    _headerAnimationController.dispose();
    _pulseAnimationController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PATIENT DATA
  // ---------------------------------------------------------------------------

  Future<void> _loadPatient({
    bool refreshing = false,
  }) async {
    if (refreshing) {
      setState(() {
        _isRefreshing = true;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final snapshot = await _firestore
          .collection('patients')
          .doc(widget.patientId)
          .get();

      if (!snapshot.exists) {
        if (!mounted) return;

        setState(() {
          _patientData = null;
          _errorMessage = 'Patient record could not be found.';
          _isLoading = false;
          _isRefreshing = false;
        });

        return;
      }

      final data = snapshot.data();

      if (data == null) {
        throw Exception('Patient data is empty.');
      }

      if (!mounted) return;

      setState(() {
        _patientData = Map<String, dynamic>.from(data);
        _errorMessage = null;
        _isLoading = false;
        _isRefreshing = false;
      });

      await _loadDoctorName(
        (_patientData?['assignedDoctor'] ?? '').toString(),
      );

      if (mounted) {
        _headerAnimationController.reset();
        _headerAnimationController.forward();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to load the patient record.';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadDoctorName(String doctorId) async {
    if (doctorId.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        _doctorName = 'Not assigned';
      });

      return;
    }

    try {
      final snapshot =
      await _firestore.collection('users').doc(doctorId).get();

      if (!mounted) return;

      if (!snapshot.exists) {
        setState(() {
          _doctorName = 'Doctor not found';
        });

        return;
      }

      final data = snapshot.data();

      setState(() {
        _doctorName = (data?['name'] ?? 'Unknown Doctor').toString();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _doctorName = 'Unable to load doctor';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // VOICE INITIALIZATION
  // ---------------------------------------------------------------------------

  Future<bool> _initializeSpeech() async {
    if (_speechInitialized) {
      return true;
    }

    try {
      final available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: false,
      );

      if (!mounted) return false;

      setState(() {
        _speechInitialized = available;
        _voiceError = available
            ? null
            : 'Speech recognition is unavailable on this device.';
      });

      return available;
    } catch (_) {
      if (!mounted) return false;

      setState(() {
        _speechInitialized = false;
        _voiceError = 'Unable to initialize the microphone.';
      });

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // MICROPHONE
  // ---------------------------------------------------------------------------

  Future<void> _toggleListening() async {
    if (_isProcessingCommand) {
      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    if (_isProcessingCommand || _isListening) {
      return;
    }

    final initialized = await _initializeSpeech();

    if (!initialized || !mounted) {
      await _speak(
        'Speech recognition is unavailable.',
      );
      return;
    }

    try {
      _silenceTimer?.cancel();

      setState(() {
        _isListening = true;
        _voiceText = '';
        _voiceError = null;
      });

      _pulseAnimationController.repeat(
        reverse: true,
      );

      await _speech.listen(
        onResult: _handleSpeechResult,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.confirmation,
        onSoundLevelChange: (_) {
          // Sound-level callback intentionally kept lightweight.
          // The speech plugin manages microphone audio internally.
        },
      );

      _restartSilenceTimer();
    } catch (_) {
      await _stopListening(
        speakConfirmation: false,
      );

      if (!mounted) return;

      setState(() {
        _voiceError = 'Unable to start the microphone.';
      });
    }
  }

  Future<void> _stopListening({
    bool speakConfirmation = false,
    bool clearText = false,
  }) async {
    _silenceTimer?.cancel();

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {
      // Ignore microphone shutdown errors.
    }

    _pulseAnimationController.stop();
    _pulseAnimationController.reset();

    final shouldProcess =
        _voiceText.trim().isNotEmpty && !clearText && mounted;

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }

    if (speakConfirmation) {
      await _speak('Listening stopped.');
    }

    if (shouldProcess) {
      await _processVoiceCommand(_voiceText);
    }
  }

  void _restartSilenceTimer() {
    _silenceTimer?.cancel();

    if (!_isListening) {
      return;
    }

    _silenceTimer = Timer(
      _silenceTimeout,
          () async {
        if (!mounted || !_isListening) {
          return;
        }

        await _stopListening();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SPEECH CALLBACKS
  // ---------------------------------------------------------------------------

  void _handleSpeechResult(stt.SpeechRecognitionResult result) {
    if (!mounted) return;

    final recognizedText = result.recognizedWords.trim();

    setState(() {
      _voiceText = recognizedText;
      _voiceError = null;
    });

    if (recognizedText.isNotEmpty) {
      _restartSilenceTimer();
    }

    if (result.finalResult) {
      _silenceTimer?.cancel();

      Future.microtask(() async {
        if (!mounted) return;

        await _stopListening();
      });
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;

    final normalized = status.toLowerCase();

    if (normalized == 'done' ||
        normalized == 'not listening' ||
        normalized == 'inactive') {
      _silenceTimer?.cancel();

      if (_isListening && !_isProcessingCommand) {
        setState(() {
          _isListening = false;
        });

        _pulseAnimationController.stop();
        _pulseAnimationController.reset();

        if (_voiceText.trim().isNotEmpty) {
          Future.microtask(() async {
            if (mounted) {
              await _processVoiceCommand(_voiceText);
            }
          });
        }
      }
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) return;

    _silenceTimer?.cancel();

    _pulseAnimationController.stop();
    _pulseAnimationController.reset();

    setState(() {
      _isListening = false;
      _voiceError = _friendlySpeechError(error);
    });
  }

  String _friendlySpeechError(dynamic error) {
    final message = error.toString().toLowerCase();

    if (message.contains('permission')) {
      return 'Microphone permission is required.';
    }

    if (message.contains('network')) {
      return 'Speech recognition requires a network connection.';
    }

    if (message.contains('timeout')) {
      return 'No speech was detected.';
    }

    if (message.contains('not available')) {
      return 'Speech recognition is unavailable.';
    }

    return 'Speech recognition encountered an error.';
  }

  // ---------------------------------------------------------------------------
  // PROFESSIONAL VOICE PARSER
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> interpretVoiceCommand(
      String command,
      ) async {
    String text = command
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[,!?;:]+'), ' ')
        .replaceAll(RegExp(r'[-_/]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) {
      return {
        'intent': 'unknown',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // Filler / polite phrases.
    // These are removed without changing meaningful medical terminology.
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
      RegExp(r'\bbring up\b'),
      'open ',
    )
        .replaceAll(
      RegExp(r'\blook at\b'),
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

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // -------------------------------------------------------------------------
    // LOGOUT
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(logout|log out|sign out|signout|exit account|exit)$',
    ).hasMatch(text)) {
      return {
        'intent': 'logout',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // PROFILE
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(profile|my profile|open profile|show profile|view profile|account)$',
    ).hasMatch(text)) {
      return {
        'intent': 'view_profile',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // BACK
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(back|go back|go backward|previous|previous page|return|return back)$',
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
      r'^(patient details|show patient details|show details|patient information|patient info|details)$',
    ).hasMatch(text)) {
      return {
        'intent': 'show_patient_details',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // DOCUMENTS
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(open|show|display|view|list|get)\s+'
      r'(?:the\s+)?'
      r'(all\s+)?'
      r'(documents|files|patient documents|patient files)$',
    ).hasMatch(text)) {
      return {
        'intent': 'open_documents',
        'parameter': null,
      };
    }

    // -------------------------------------------------------------------------
    // SPECIFIC DOCUMENT
    // -------------------------------------------------------------------------

    final documentMatch = RegExp(
      r'^(?:open|show|display|view|read)'
      r'\s+(?:the\s+)?'
      r'(?:document|file|report)'
      r'(?:\s+(.+))?$',
    ).firstMatch(text);

    if (documentMatch != null) {
      final parameter = documentMatch.group(1)?.trim();

      return {
        'intent': 'open_document',
        'parameter': parameter,
      };
    }

    // -------------------------------------------------------------------------
    // PATIENT COMMANDS
    //
    // This page is already a patient detail page, so patient commands are
    // intentionally not interpreted as generic navigation.
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(find|search|open|show|display|view|get|fetch|select)\b',
    ).hasMatch(text)) {
      final patientMatch = RegExp(
        r'^(find|search|open|show|display|view|get|fetch|select)'
        r'(?:\s+(?:the\s+)?)?'
        r'(?:patient\s*)?'
        r'(?:number\s*)?'
        r'(.+)$',
      ).firstMatch(text);

      if (patientMatch != null) {
        final parameter =
            patientMatch.group(2)?.trim() ?? '';

        if (parameter.isNotEmpty) {
          return {
            'intent': 'find_patient',
            'parameter': _normalizePatientIdentifier(parameter),
          };
        }
      }
    }

    // -------------------------------------------------------------------------
    // DIRECT PATIENT ID
    //
    // Examples:
    // 9
    // 09
    // 009
    // P9
    // P 9
    // P009
    // P 009
    // -------------------------------------------------------------------------

    final directPatientId = _normalizePatientIdentifier(text);

    if (_looksLikePatientId(directPatientId)) {
      return {
        'intent': 'find_patient',
        'parameter': directPatientId,
      };
    }

    return {
      'intent': 'unknown',
      'parameter': null,
    };
  }

  String _normalizePatientIdentifier(String value) {
    String parameter = value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[,!?;:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (parameter.isEmpty) {
      return '';
    }

    // Remove patient prefix.
    parameter = parameter.replaceFirst(
      RegExp(r'^(the\s+)?patient\s+'),
      '',
    );

    parameter = parameter.replaceFirst(
      RegExp(r'^number\s+'),
      '',
    );

    // Common STT interpretations of the letter P.
    parameter = parameter.replaceFirst(
      RegExp(r'^(pee|pea)\s*'),
      'p ',
    );

    parameter = parameter.trim();

    // Number-word conversion happens ONLY when the entire candidate
    // is clearly an ID. This prevents words such as "for" in names
    // from accidentally becoming "4".
    const Map<String, String> numberWords = {
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

    final spokenNumberPattern = RegExp(
      r'^(?:p\s+)?'
      r'(zero|one|won|two|to|too|three|four|for|five|six|seven|eight|ate|nine)$',
    );

    final spokenMatch =
    spokenNumberPattern.firstMatch(parameter);

    if (spokenMatch != null) {
      final word = spokenMatch.group(1)!;
      final digit = numberWords[word]!;

      return 'P ${digit.padLeft(3, '0')}';
    }

    // "p nine" / "p 9"
    final pSpokenPattern = RegExp(
      r'^p\s+'
      r'(zero|one|won|two|to|too|three|four|for|five|six|seven|eight|ate|nine)$',
    );

    final pSpokenMatch =
    pSpokenPattern.firstMatch(parameter);

    if (pSpokenMatch != null) {
      final word = pSpokenMatch.group(1)!;
      final digit = numberWords[word]!;

      return 'P ${digit.padLeft(3, '0')}';
    }

    // P9, P 9, P09, P009.
    final pIdMatch = RegExp(
      r'^p\s*([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (pIdMatch != null) {
      final digits = pIdMatch.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    // Just 9, 09, 009.
    final pureNumberMatch = RegExp(
      r'^([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (pureNumberMatch != null) {
      final digits = pureNumberMatch.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    return parameter;
  }

  bool _looksLikePatientId(String value) {
    return RegExp(
      r'^p\s*[0-9]{1,3}$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  // ---------------------------------------------------------------------------
  // VOICE COMMAND EXECUTION
  // ---------------------------------------------------------------------------

  Future<void> _processVoiceCommand(String command) async {
    if (_isProcessingCommand) {
      return;
    }

    final cleanedCommand = command.trim();

    if (cleanedCommand.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessingCommand = true;
        _voiceError = null;
      });
    }

    try {
      final result =
      await interpretVoiceCommand(cleanedCommand);

      final intent = result['intent'];
      final parameter =
      result['parameter']?.toString().trim();

      switch (intent) {
        case 'go_back':
          await _speak('Going back.');

          if (!mounted) return;

          Navigator.of(context).pop();
          break;

        case 'show_patient_details':
          await _speak('Patient details are already open.');
          break;

        case 'open_documents':
          await _scrollToDocuments();
          await _speak('Showing patient documents.');
          break;

        case 'open_document':
          await _openDocumentByVoice(parameter);
          break;

        case 'find_patient':
        // The detail page does not perform global patient navigation.
        // The command is surfaced instead of silently doing the wrong action.
          await _speak(
            'Patient search is available from the surgeon dashboard.',
          );
          break;

        case 'logout':
          await _speak(
            'Logout is available from the surgeon dashboard.',
          );
          break;

        case 'view_profile':
          await _speak(
            'Profile is available from the surgeon dashboard.',
          );
          break;

        default:
          await _speak(
            'I did not understand that command.',
          );
      }
    } catch (_) {
      await _speak(
        'I was unable to process that command.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingCommand = false;
        });
      }
    }
  }

  Future<void> _openDocumentByVoice(String? query) async {
    final documents = _documents;

    if (documents.isEmpty) {
      await _speak('There are no documents for this patient.');
      return;
    }

    if (query == null || query.trim().isEmpty) {
      await _scrollToDocuments();
      await _speak('Showing patient documents.');
      return;
    }

    final normalizedQuery =
    query.toLowerCase().trim();

    final matchingDocument = documents.firstWhere(
          (document) {
        final url = document.toString();
        final fileName =
        _fileNameFromUrl(url).toLowerCase();

        return fileName.contains(normalizedQuery) ||
            url.toLowerCase().contains(normalizedQuery);
      },
      orElse: () => '',
    );

    if (matchingDocument.isEmpty) {
      await _scrollToDocuments();

      await _speak(
        'I could not find that document.',
      );

      return;
    }

    await _openUrl(matchingDocument);
  }

  Future<void> _scrollToDocuments() async {
    if (!mounted) return;

    await Scrollable.ensureVisible(
      _documentsSectionKey.currentContext!,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  Future<void> _speak(String message) async {
    try {
      await _tts.stop();
      await _tts.speak(message);
    } catch (_) {
      // Voice feedback should never crash the application.
    }
  }

  // ---------------------------------------------------------------------------
  // DOCUMENTS
  // ---------------------------------------------------------------------------

  List<String> get _documents {
    final rawDocuments =
    _patientData?['documents'];

    if (rawDocuments is! List) {
      return <String>[];
    }

    return rawDocuments
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  String _fileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);

      if (uri.pathSegments.isNotEmpty) {
        return Uri.decodeComponent(
          uri.pathSegments.last,
        );
      }
    } catch (_) {
      // Fall through to basic extraction.
    }

    final cleanUrl = url.split('?').first;

    if (cleanUrl.contains('/')) {
      return cleanUrl.split('/').last;
    }

    return cleanUrl;
  }

  String _documentExtension(String url) {
    final fileName = _fileNameFromUrl(url);
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex == -1 ||
        dotIndex == fileName.length - 1) {
      return 'FILE';
    }

    return fileName
        .substring(dotIndex + 1)
        .toUpperCase();
  }

  IconData _documentIcon(String url) {
    final extension =
    _documentExtension(url).toLowerCase();

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;

      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return Icons.image_rounded;

      case 'doc':
      case 'docx':
        return Icons.description_rounded;

      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;

      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);

      if (uri == null) {
        throw Exception('Invalid document URL');
      }

      final canOpen = await canLaunchUrl(uri);

      if (!canOpen) {
        throw Exception('Unable to open document');
      }

      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF172A3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFF6B6B),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Unable to open this document.',
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CLIPBOARD
  // ---------------------------------------------------------------------------

  Future<void> _copyPatientId() async {
    final patientId =
    (_patientData?['patientId'] ?? widget.patientId)
        .toString();

    await Clipboard.setData(
      ClipboardData(text: patientId),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF123A56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: const Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF22D3EE),
            ),
            SizedBox(width: 10),
            Text('Patient ID copied'),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _stringValue(
      dynamic value, {
        String fallback = 'N/A',
      }) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  String _createdAtText(dynamic value) {
    if (value == null) {
      return 'N/A';
    }

    try {
      if (value is Timestamp) {
        return DateFormat(
          'MMM d, yyyy • hh:mm a',
        ).format(value.toDate());
      }

      if (value is DateTime) {
        return DateFormat(
          'MMM d, yyyy • hh:mm a',
        ).format(value);
      }
    } catch (_) {
      return 'N/A';
    }

    return 'N/A';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'PT';
    }

    if (parts.length == 1) {
      return parts.first
          .substring(
        0,
        parts.first.length >= 2 ? 2 : 1,
      )
          .toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'
        .toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  final GlobalKey _documentsSectionKey =
  GlobalKey();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF071521),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF071521),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF071521),
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null || _patientData == null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      color: const Color(0xFF22D3EE),
      backgroundColor: const Color(0xFF102A3D),
      onRefresh: () => _loadPatient(refreshing: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: _buildTopBar(),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: SlideTransition(
                position: _headerSlideAnimation,
                child: _buildPatientHero(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: _buildKpis(),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: _buildPatientInformation(),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: _buildDoctorSection(),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: _buildDocumentsSection(),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP BAR
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        10,
        18,
        12,
      ),
      child: Row(
        children: [
          _buildTopBarButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PATIENT RECORD',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.7,
                    color: Color(0xFF22D3EE),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Patient Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          _buildTopBarButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _isRefreshing
                ? null
                : () => _loadPatient(refreshing: true),
          ),
          const SizedBox(width: 8),
          _buildVoiceButton(),
        ],
      ),
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null
                  ? Colors.white24
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOICE BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildVoiceButton() {
    final listening = _isListening;

    return Tooltip(
      message: listening
          ? 'Stop listening'
          : 'Voice command',
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = listening
              ? _pulseAnimation.value
              : 1.0;

          return Transform.scale(
            scale: scale,
            child: Material(
              color: listening
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF0E7490),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: _isProcessingCommand
                    ? null
                    : _toggleListening,
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    listening
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PATIENT HERO
  // ---------------------------------------------------------------------------

  Widget _buildPatientHero() {
    final name = _stringValue(
      _patientData?['name'],
      fallback: 'Unknown Patient',
    );

    final patientId = _stringValue(
      _patientData?['patientId'],
      fallback: widget.patientId,
    );

    final age = _stringValue(
      _patientData?['age'],
    );

    final gender = _stringValue(
      _patientData?['gender'],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(
        18,
        4,
        18,
        16,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF123A56),
            Color(0xFF0B2B40),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF22D3EE).withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E7490).withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withOpacity(0.45),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          size: 15,
                          color: Color(0xFF9DB2C1),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            patientId,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB6C8D3),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy patient ID',
                onPressed: _copyPatientId,
                icon: const Icon(
                  Icons.copy_rounded,
                  color: Color(0xFF9DB2C1),
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.08),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.cake_outlined,
                  label: 'Age',
                  value: age,
                ),
              ),
              _buildVerticalDivider(),
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.wc_rounded,
                  label: 'Gender',
                  value: gender,
                ),
              ),
              _buildVerticalDivider(),
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.verified_user_outlined,
                  label: 'Status',
                  value: 'Active',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF22D3EE),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8299A8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white.withOpacity(0.08),
      margin: const EdgeInsets.symmetric(horizontal: 7),
    );
  }

  // ---------------------------------------------------------------------------
  // KPI CARDS
  // ---------------------------------------------------------------------------

  Widget _buildKpis() {
    final documents = _documents;

    final createdAt =
    _createdAtText(_patientData?['createdAt']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 650;

          final cards = [
            _buildKpiCard(
              icon: Icons.folder_copy_outlined,
              value: documents.length.toString(),
              label: 'Documents',
            ),
            _buildKpiCard(
              icon: Icons.calendar_today_outlined,
              value: createdAt == 'N/A'
                  ? 'N/A'
                  : createdAt.split(' • ').first,
              label: 'Record Created',
            ),
            _buildKpiCard(
              icon: Icons.medical_services_outlined,
              value: _doctorName ?? 'Loading',
              label: 'Assigned Doctor',
            ),
          ];

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 10),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 10),
                cards[2],
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
              const SizedBox(width: 10),
              Expanded(child: cards[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 82,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2435),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0E7490).withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 19,
              color: const Color(0xFF22D3EE),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8299A8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PATIENT INFORMATION
  // ---------------------------------------------------------------------------

  Widget _buildPatientInformation() {
    final phone = _stringValue(
      _patientData?['phone'],
    );

    final email = _stringValue(
      _patientData?['email'],
    );

    final createdAt =
    _createdAtText(_patientData?['createdAt']);

    return _buildSection(
      title: 'Patient Information',
      subtitle: 'Contact and record metadata',
      icon: Icons.person_outline_rounded,
      child: Column(
        children: [
          _buildInformationRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phone,
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: email,
          ),
          _buildInformationDivider(),
          _buildInformationRow(
            icon: Icons.schedule_rounded,
            label: 'Record Created',
            value: createdAt,
          ),
        ],
      ),
    );
  }

  Widget _buildInformationRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 13,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF123A56).withOpacity(0.55),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF22D3EE),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9DB2C1),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
      color: Colors.white.withOpacity(0.055),
    );
  }

  // ---------------------------------------------------------------------------
  // DOCTOR
  // ---------------------------------------------------------------------------

  Widget _buildDoctorSection() {
    final doctor = _doctorName ?? 'Loading doctor...';

    return _buildSection(
      title: 'Assigned Doctor',
      subtitle: 'Current clinical responsibility',
      icon: Icons.medical_services_outlined,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF0B2A3C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF22D3EE).withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0E7490).withOpacity(0.2),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF22D3EE),
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assigned Physician',
                    style: TextStyle(
                      color: Color(0xFF8299A8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    doctor,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF22D3EE).withOpacity(0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: Color(0xFF22D3EE),
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Assigned',
                    style: TextStyle(
                      color: Color(0xFF22D3EE),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DOCUMENTS
  // ---------------------------------------------------------------------------

  Widget _buildDocumentsSection() {
    final documents = _documents;

    return Container(
      key: _documentsSectionKey,
      child: _buildSection(
        title: 'Documents',
        subtitle: documents.isEmpty
            ? 'No clinical documents available'
            : '${documents.length} document${documents.length == 1 ? '' : 's'} attached',
        icon: Icons.folder_open_rounded,
        child: documents.isEmpty
            ? _buildEmptyDocuments()
            : Column(
          children: List.generate(
            documents.length,
                (index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == documents.length - 1
                      ? 0
                      : 10,
                ),
                child: _buildDocumentCard(
                  documents[index],
                  index,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(
      String url,
      int index,
      ) {
    final fileName = _fileNameFromUrl(url);
    final extension = _documentExtension(url);

    return Material(
      color: const Color(0xFF0D2435),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openUrl(url),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.065),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF123A56),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _documentIcon(url),
                  color: const Color(0xFF22D3EE),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            extension,
                            style: const TextStyle(
                              color: Color(0xFF22D3EE),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Document ${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFF718896),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF123A56),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.open_in_new_rounded,
                  color: Color(0xFFB6C8D3),
                  size: 17,
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
      padding: const EdgeInsets.symmetric(
        vertical: 30,
        horizontal: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2435),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 36,
            color: Color(0xFF627B89),
          ),
          SizedBox(height: 10),
          Text(
            'No documents uploaded',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Patient reports and clinical files will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF718896),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION CONTAINER
  // ---------------------------------------------------------------------------

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        18,
      ),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF091D2B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E7490).withOpacity(0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF22D3EE),
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF718896),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOADING
  // ---------------------------------------------------------------------------

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFF0E7490).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.18),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(21),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF22D3EE),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Loading patient record',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Retrieving clinical information...',
              style: TextStyle(
                color: Color(0xFF718896),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFDC2626).withOpacity(0.22),
                ),
              ),
              child: const Icon(
                Icons.person_off_outlined,
                color: Color(0xFFFF6B6B),
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Patient record unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _errorMessage ??
                  'The requested patient record could not be loaded.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8299A8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _loadPatient(),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 17,
                  ),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF22D3EE),
                    side: BorderSide(
                      color: const Color(0xFF22D3EE)
                          .withOpacity(0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Go Back',
                    style: TextStyle(
                      color: Color(0xFF9DB2C1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}