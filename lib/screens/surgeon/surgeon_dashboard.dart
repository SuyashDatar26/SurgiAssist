import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:surgiassist_ibip_lnct/screens/login_page.dart';
import 'package:surgiassist_ibip_lnct/screens/surgeon/procedure_summary.dart';

import '../../secrets.dart';
import '../admin/patient_history.dart';
import '../pdfview_page.dart';

class SurgeonDashboard extends StatefulWidget {
  const SurgeonDashboard({super.key});

  @override
  State<SurgeonDashboard> createState() => _SurgeonDashboardState();
}

class _SurgeonDashboardState extends State<SurgeonDashboard>
    with TickerProviderStateMixin {

  bool _isProcessingVoiceCommand = false;
  bool _isNavigating = false;
  int _speechGeneration = 0;


  // ===========================================================================
  // COLORS
  // ===========================================================================

  static const Color _background = Color(0xFF06131F);
  static const Color _surface = Color(0xFF0B1F33);
  static const Color _surfaceLight = Color(0xFF102B40);
  static const Color _surfaceLighter = Color(0xFF16384E);

  static const Color _primary = Color(0xFF22D3EE);
  static const Color _primaryDark = Color(0xFF0E7490);
  static const Color _teal = Color(0xFF14B8A6);

  static const Color _textPrimary = Color(0xFFF4FAFC);
  static const Color _textSecondary = Color(0xFF9DB2C1);
  static const Color _textMuted = Color(0xFF6F8797);

  static const Color _success = Color(0xFF22C55E);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  // ===========================================================================
  // SPEECH
  // ===========================================================================

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _speechAvailable = false;

  Timer? _silenceTimer;

  String _voiceText = '';

  // ===========================================================================
  // PATIENTS
  // ===========================================================================

  List<DocumentSnapshot> _searchResults = [];

  String _patientSearchText = '';

  bool _isSearching = false;

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  late TabController _tabController;

  late AnimationController _pageAnimationController;
  late AnimationController _micAnimationController;
  late AnimationController _pulseAnimationController;
  late AnimationController _floatingAnimationController;

  late Animation<double> _pageFadeAnimation;
  late Animation<Offset> _pageSlideAnimation;

  final TextEditingController _patientSearchController =
  TextEditingController();

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 3,
      vsync: this,
    );

    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _pageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _pageFadeAnimation = CurvedAnimation(
      parent: _pageAnimationController,
      curve: Curves.easeOutCubic,
    );

    _pageSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _floatingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _pageAnimationController.forward();

    _initializeSpeech();
  }

  // ===========================================================================
  // SPEECH INITIALIZATION
  // ===========================================================================

// ===========================================================================
// SPEECH INITIALIZATION
// ===========================================================================

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) {
            return;
          }

          // ---------------------------------------------------------------------
          // IMPORTANT:
          //
          // The dashboard remains mounted underneath PatientHistoryPage.
          // Therefore mounted == true does NOT mean that this page is active.
          //
          // Never allow speech callbacks to process commands while another
          // page is sitting above the dashboard.
          // ---------------------------------------------------------------------

          if (!_isDashboardActive()) {
            debugPrint(
              '🎙️ Ignoring speech status "$status" because dashboard is inactive.',
            );
            return;
          }

          if (_isNavigating ||
              _isProcessingVoiceCommand ||
              !_isListening) {
            return;
          }

          if (status.toLowerCase().trim() == 'done' ||
              status.toLowerCase().trim() == 'not listening' ||
              status.toLowerCase().trim() == 'inactive') {
            _handleSpeechFinished();
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }

          // Ignore errors generated by an intentionally cancelled recognition
          // session, especially while navigating away.
          if (_isNavigating ||
              !_isDashboardActive()) {
            debugPrint(
              '🎙️ Ignoring speech error during navigation: ${error.errorMsg}',
            );
            return;
          }

          _stopListeningVisuals();

          _showSnackBar(
            "Speech error: ${error.errorMsg}",
            _danger,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _speechAvailable = available;
      });
    } catch (e) {
      debugPrint(
        'Speech initialization error: $e',
      );
    }
  }


  // ===========================================================================
// CHECK WHETHER SURGEON DASHBOARD IS CURRENTLY ACTIVE
// ===========================================================================
//
// A StatefulWidget can remain mounted even when another route is displayed
// above it.
//
// Example:
//
// SurgeonDashboard
//      ↓
// PatientHistoryPage
//
// In this situation SurgeonDashboard is still mounted, but it must NOT react
// to speech callbacks.
//
// ===========================================================================

  bool _isDashboardActive() {
    if (!mounted) {
      return false;
    }

    if (_isNavigating) {
      return false;
    }

    final route = ModalRoute.of(context);

    if (route == null) {
      return false;
    }

    return route.isCurrent;
  }


  // ===========================================================================
  // GEMINI
  // ===========================================================================

  Future<String?> _getClosestMedicalTerm(String query) async {
    try {
      final model = GenerativeModel(
        model: "gemini-2.5-flash",
        apiKey: GEMINI_API_KEY,
      );

      final prompt = """
You are a medical terminology assistant.

The user said:
"$query"

Your job:
- Correct spelling if needed.
- Interpret slang.
- Identify the closest real medical procedure or surgery.
- Reply ONLY with the correct medical term.
- Do NOT add extra text.

If no real medical procedure matches, reply with only:
UNKNOWN
""";

      final response = await model.generateContent([
        Content.text(prompt),
      ]);

      final answer = response.text?.trim() ?? "";

      if (answer.toUpperCase() == "UNKNOWN") {
        return null;
      }

      return answer;
    } catch (e) {
      debugPrint("Medical term correction error: $e");
      return null;
    }
  }

// ===========================================================================
// VOICE COMMAND INTERPRETATION
// ===========================================================================
//
// Robust speech-to-text command parser.
//
// Supported examples:
//
// PATIENTS
//   "find John"
//   "find patient John"
//   "search John"
//   "search for John"
//   "open patient John"
//   "show patient John"
//   "get patient John"
//   "fetch patient John"
//
// PATIENT IDS
//   "9"
//   "9"
//   "patient 9"
//   "find 9"
//   "find patient 9"
//   "P 9"
//   "P9"
//   "pee 9"
//   "pee nine"
//   "P nine"
//   "patient P nine"
//   "find patient P 9"
//   "find patient number 9"
//   "open patient number nine"
//   "fetch patient P 009"
//
// MEDICAL
//   "search procedure appendectomy"
//   "search surgery appendectomy"
//   "search workflow appendectomy"
//   "lookup appendectomy"
//   "explain appendectomy"
//
// DOCUMENTS
//   "open documents"
//   "show documents"
//   "open document xray"
//   "show file report"
//
// NAVIGATION / ACCOUNT
//   "back"
//   "go back"
//   "profile"
//   "open profile"
//   "logout"
//   "log out"
//   "sign out"
// ===========================================================================

  Future<Map<String, dynamic>> interpretVoiceCommandOffline(
      String command) async {
    // -------------------------------------------------------------------------
    // 1. BASIC SPEECH-TO-TEXT NORMALIZATION
    // -------------------------------------------------------------------------

    String text = command
        .toLowerCase()
        .trim();

    if (text.isEmpty) {
      return {
        "intent": "unknown",
      };
    }

    // Normalize punctuation that speech recognition may insert.
    text = text
        .replaceAll(RegExp(r'[,!?;:]+'), ' ')
        .replaceAll(RegExp(r'[-_/]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Common STT variations.
    text = text
        .replaceAll(RegExp(r'\bgoing to\b'), ' ')
        .replaceAll(RegExp(r'\bplease\b'), ' ')
        .replaceAll(RegExp(r'\bkindly\b'), ' ')
        .replaceAll(RegExp(r'\bcan you\b'), ' ')
        .replaceAll(RegExp(r'\bcould you\b'), ' ')
        .replaceAll(RegExp(r'\bwould you\b'), ' ')
        .replaceAll(RegExp(r'\bi want to\b'), ' ')
        .replaceAll(RegExp(r'\bi would like to\b'), ' ')
        .replaceAll(RegExp(r'\bi need to\b'), ' ')
        .replaceAll(RegExp(r'\bcan i\b'), ' ')
        .replaceAll(RegExp(r'\bshow me\b'), 'show ')
        .replaceAll(RegExp(r'\btake me to\b'), 'open ')
        .replaceAll(RegExp(r'\bgo to\b'), 'open ')
        .replaceAll(RegExp(r'\bbring up\b'), 'open ')
        .replaceAll(RegExp(r'\bbring me\b'), 'open ')
        .replaceAll(RegExp(r'\blook for\b'), 'find ')
        .replaceAll(RegExp(r'\blook up\b'), 'lookup ')
        .replaceAll(RegExp(r'\bsearch for\b'), 'search ')
        .replaceAll(RegExp(r'\bfind for\b'), 'find ');

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.isEmpty) {
      return {
        "intent": "unknown",
      };
    }

    // -------------------------------------------------------------------------
    // 2. NORMALIZE COMMON SPOKEN NUMBER WORDS
    // -------------------------------------------------------------------------
    //
    // This is deliberately done before patient-ID detection.
    //
    // Examples:
    //   "P nine"       -> "p 9"
    //   "patient nine" -> "patient 9"
    //   "find zero nine" -> "find 0 9"
    //
    // We also handle common STT variants such as:
    //   "to" -> "two"
    //   "for" -> "four"
    //   "ate" -> "eight"
    // -------------------------------------------------------------------------

    const Map<String, String> numberWords = {
      "zero": "0",
      "one": "1",
      "won": "1",
      "two": "2",
      "to": "2",
      "too": "2",
      "three": "3",
      "four": "4",
      "for": "4",
      "five": "5",
      "six": "6",
      "seven": "7",
      "eight": "8",
      "ate": "8",
      "nine": "9",
    };

    final numberPattern = RegExp(
      r'\b(zero|one|won|two|to|too|three|four|for|five|six|seven|eight|ate|nine)\b',
    );

    text = text.replaceAllMapped(
      numberPattern,
          (match) => numberWords[match.group(0)!]!,
    );

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // -------------------------------------------------------------------------
    // 3. LOGOUT
    // -------------------------------------------------------------------------
    //
    // Use exact/anchored matching rather than contains().
    // This prevents accidental matches inside other commands.
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(logout|log out|sign out|signout|exit account|exit)$',
    ).hasMatch(text)) {
      return {
        "intent": "logout",
      };
    }

    // -------------------------------------------------------------------------
    // 4. PROFILE
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(profile|my profile|open profile|show profile|view profile|account)$',
    ).hasMatch(text)) {
      return {
        "intent": "view_profile",
      };
    }

    // -------------------------------------------------------------------------
    // 5. SHOW ALL PATIENTS
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(show|display|view|list|get)\s+all\s+(patients|patient records)$',
    ).hasMatch(text)) {
      return {
        "intent": "show_all_patients",
      };
    }

    // -------------------------------------------------------------------------
    // 6. OPEN ALL DOCUMENTS
    // -------------------------------------------------------------------------
    //
    // This MUST be checked before single-document parsing.
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(open|show|display|view|list)\s+'
      r'(all\s+)?(documents|files|patient documents|patient files)$',
    ).hasMatch(text)) {
      return {
        "intent": "open_documents",
      };
    }

    // -------------------------------------------------------------------------
    // 7. MEDICAL SEARCH
    // -------------------------------------------------------------------------
    //
    // IMPORTANT:
    // This is checked BEFORE generic "search" patient commands.
    //
    // The old parser used contains("search"), which could cause:
    //
    //   "search procedure appendectomy"
    //
    // to fall into patient search if the medical branch failed to extract
    // the parameter correctly.
    // -------------------------------------------------------------------------

    final medicalMatch = RegExp(
      r'^(?:'
      r'search\s+(?:for\s+)?(?:a\s+)?(?:medical\s+)?(?:procedure|surgery|operation|workflow)'
      r'|'
      r'look\s*up'
      r'|'
      r'lookup'
      r'|'
      r'explain'
      r'|'
      r'tell\s+me\s+about'
      r'|'
      r'give\s+me\s+information\s+(?:about|on)'
      r')'
      r'(?:\s+(.+))?$',
    ).firstMatch(text);

    if (medicalMatch != null) {
      final parameter = medicalMatch.group(1)?.trim();

      if (parameter != null && parameter.isNotEmpty) {
        return {
          "intent": "search_medical",
          "parameter": parameter,
        };
      }

      return {
        "intent": "search_medical",
        "parameter": null,
      };
    }

    // -------------------------------------------------------------------------
    // 8. DOCUMENT WITH SPECIFIC NAME
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
        "intent": "open_document",
        "parameter": parameter,
      };
    }

    // -------------------------------------------------------------------------
    // 9. BACK / NAVIGATION
    // -------------------------------------------------------------------------

    if (RegExp(
      r'^(back|go back|go backward|previous|previous page|return|return back)$',
    ).hasMatch(text)) {
      return {
        "intent": "go_back",
      };
    }

    // -------------------------------------------------------------------------
    // 10. PATIENT COMMAND
    // -------------------------------------------------------------------------
    //
    // This is intentionally LAST among the search-like commands.
    //
    // Accepted:
    //
    //   find John
    //   search John
    //   open patient John
    //   show patient John
    //   get patient John
    //   fetch patient John
    //   find patient John
    //   find patient number 9
    //
    // And importantly:
    //
    //   9
    //   P 9
    //   P9
    //   P nine
    //   pee 9
    //   pee nine
    //
    // are all interpreted as patient searches.
    // -------------------------------------------------------------------------

    final patientMatch = RegExp(
      r'^(?:'
      r'find'
      r'|search'
      r'|open'
      r'|show'
      r'|display'
      r'|view'
      r'|get'
      r'|fetch'
      r'|select'
      r')'
      r'(?:\s+(?:the\s+)?)?'
      r'(?:patient\s*)?'
      r'(?:number\s*)?'
      r'(.+)$',
    ).firstMatch(text);

    if (patientMatch != null) {
      String parameter = patientMatch.group(1)?.trim() ?? '';

      // Remove trailing filler words commonly produced by STT.
      parameter = parameter
          .replaceFirst(
        RegExp(r'\s+(please|thanks|thank you)$'),
        '',
      )
          .trim();

      if (parameter.isNotEmpty) {
        return {
          "intent": "find_patient",
          "parameter": _normalizeVoicePatientParameter(parameter),
        };
      }

      return {
        "intent": "unknown",
      };
    }

    // -------------------------------------------------------------------------
    // 11. DIRECT PATIENT ID WITHOUT A COMMAND
    // -------------------------------------------------------------------------
    //
    // This is important for:
    //
    //   "9"
    //   "P 9"
    //   "P9"
    //   "pee 9"
    //   "patient 9"
    //
    // The user does NOT have to say "find".
    // -------------------------------------------------------------------------

    final directPatientParameter =
    _normalizeVoicePatientParameter(text);

    if (_looksLikePatientId(directPatientParameter)) {
      return {
        "intent": "find_patient",
        "parameter": directPatientParameter,
      };
    }

    // -------------------------------------------------------------------------
    // 12. SIMPLE NATURAL-LANGUAGE PATIENT REQUESTS
    // -------------------------------------------------------------------------
    //
    // These handle commands such as:
    //
    //   "patient John"
    //   "patient P 9"
    //   "the patient John"
    //   "the patient P 9"
    // -------------------------------------------------------------------------

    final naturalPatientMatch = RegExp(
      r'^(?:the\s+)?patient\s+(?:number\s+)?(.+)$',
    ).firstMatch(text);

    if (naturalPatientMatch != null) {
      final parameter =
      _normalizeVoicePatientParameter(
        naturalPatientMatch.group(1)?.trim() ?? '',
      );

      if (parameter.isNotEmpty) {
        return {
          "intent": "find_patient",
          "parameter": parameter,
        };
      }
    }

    // -------------------------------------------------------------------------
    // 13. UNKNOWN
    // -------------------------------------------------------------------------

    return {
      "intent": "unknown",
    };
  }


// ===========================================================================
// NORMALIZE PATIENT PARAMETER FROM SPEECH
// ===========================================================================
//
// This helper makes patient IDs tolerant to speech-recognition variations.
//
// Examples:
//
//   "P 9"             -> "P 009"
//   "P9"              -> "P 009"
//   "p nine"          -> "P 009"
//   "pee 9"           -> "P 009"
//   "pee nine"        -> "P 009"
//   "patient 9"       -> "P 009"
//   "patient number 9"-> "P 009"
//   "009"             -> "P 009"
//   "9"               -> "P 009"
//   "P 12"            -> "P 012"
//   "P 123"           -> "P 123"
//
// Names are NOT converted.
// Example:
//   "John Smith" -> "John Smith"
// ===========================================================================

  String _normalizeVoicePatientParameter(String value) {
    String parameter = value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[,!?;:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (parameter.isEmpty) {
      return '';
    }

    // Remove common speech filler around a patient reference.
    parameter = parameter
        .replaceFirst(
      RegExp(r'^(the\s+)?patient\s+'),
      '',
    )
        .replaceFirst(
      RegExp(r'^number\s+'),
      '',
    )
        .trim();

    // "pee" / "pea" are very common STT interpretations of "P".
    parameter = parameter
        .replaceFirst(
      RegExp(r'^(pee|pea)\s*'),
      'p ',
    )
        .trim();

    // Normalize "patient p nine", etc.
    parameter = parameter
        .replaceFirst(
      RegExp(r'^patient\s+'),
      '',
    )
        .trim();

    // -------------------------------------------------------------------------
    // NUMBER WORDS
    // -------------------------------------------------------------------------

    const Map<String, String> numberWords = {
      "zero": "0",
      "one": "1",
      "won": "1",
      "two": "2",
      "to": "2",
      "too": "2",
      "three": "3",
      "four": "4",
      "for": "4",
      "five": "5",
      "six": "6",
      "seven": "7",
      "eight": "8",
      "ate": "8",
      "nine": "9",
    };

    final numberPattern = RegExp(
      r'\b(zero|one|won|two|to|too|three|four|for|five|six|seven|eight|ate|nine)\b',
    );

    parameter = parameter.replaceAllMapped(
      numberPattern,
          (match) => numberWords[match.group(0)!]!,
    );

    parameter = parameter
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // -------------------------------------------------------------------------
    // P + DIGITS
    // -------------------------------------------------------------------------
    //
    // "P 9", "P9", "P 09", "P 009", "pee 9" etc.
    // -------------------------------------------------------------------------

    final pIdMatch = RegExp(
      r'^p\s*([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (pIdMatch != null) {
      final digits = pIdMatch.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    // -------------------------------------------------------------------------
    // PURE DIGIT PATIENT ID
    // -------------------------------------------------------------------------
    //
    // This is the important new behavior:
    //
    //   "9"   -> "P 009"
    //   "12"  -> "P 012"
    //   "123" -> "P 123"
    //
    // Therefore the surgeon only needs to say the number.
    // -------------------------------------------------------------------------

    final pureNumberMatch = RegExp(
      r'^([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (pureNumberMatch != null) {
      final digits = pureNumberMatch.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    // -------------------------------------------------------------------------
    // "PATIENT NUMBER 9"
    // -------------------------------------------------------------------------

    final patientNumberMatch = RegExp(
      r'^(?:patient\s+)?number\s*([0-9]{1,3})$',
    ).firstMatch(parameter);

    if (patientNumberMatch != null) {
      final digits = patientNumberMatch.group(1)!;

      return 'P ${digits.padLeft(3, '0')}';
    }

    // -------------------------------------------------------------------------
    // RETURN NORMAL PATIENT NAME
    // -------------------------------------------------------------------------

    return parameter;
  }


// ===========================================================================
// CHECK WHETHER A VALUE LOOKS LIKE A PATIENT ID
// ===========================================================================

  bool _looksLikePatientId(String value) {
    final normalized = value
        .toLowerCase()
        .trim();

    return RegExp(
      r'^(?:p\s*)?[0-9]{1,3}$',
    ).hasMatch(normalized);
  }


  // ===========================================================================
  // START LISTENING
  // ===========================================================================

// ===========================================================================
// START LISTENING
// ===========================================================================

  Future<void> _startListening() async {
    // -------------------------------------------------------------------------
    // NEVER start recognition if the dashboard is not currently visible.
    // -------------------------------------------------------------------------

    if (!_isDashboardActive() ||
        _isProcessingVoiceCommand) {
      debugPrint(
        '🎙️ Start listening ignored because dashboard is not available.',
      );
      return;
    }

    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!mounted ||
        !_isDashboardActive()) {
      return;
    }

    if (!_speechAvailable) {
      _showSnackBar(
        "Speech recognition is not available on this device.",
        _danger,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // Every new microphone session gets a unique generation.
    //
    // Any callback belonging to an older generation is ignored.
    // -------------------------------------------------------------------------

    final int generation = ++_speechGeneration;

    try {
      // Completely terminate any previous recognition session first.
      try {
        await _speech.cancel();
      } catch (_) {}

      if (!mounted ||
          generation != _speechGeneration ||
          !_isDashboardActive() ||
          _isProcessingVoiceCommand) {
        return;
      }

      setState(() {
        _isListening = true;
        _voiceText = '';
      });

      _micAnimationController.repeat();
      _pulseAnimationController.repeat();

      await _speech.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,

        onResult: (result) async {
          // -------------------------------------------------------------------
          // STALE CALLBACK PROTECTION
          // -------------------------------------------------------------------

          if (!mounted ||
              generation != _speechGeneration ||
              !_isListening ||
              _isNavigating ||
              _isProcessingVoiceCommand ||
              !_isDashboardActive()) {
            debugPrint(
              '🎙️ Ignoring stale speech result.',
            );
            return;
          }

          final recognizedText =
          result.recognizedWords.trim();

          if (recognizedText.isEmpty) {
            return;
          }

          setState(() {
            _voiceText = recognizedText;
          });

          _silenceTimer?.cancel();

          // -------------------------------------------------------------------
          // FINAL RESULT
          //
          // Do not process directly from multiple callback paths.
          // _processVoiceCommand() has its own processing lock and generation
          // validation.
          // -------------------------------------------------------------------

          if (result.finalResult) {
            await _processVoiceCommand(
              expectedGeneration: generation,
            );

            return;
          }

          // -------------------------------------------------------------------
          // PARTIAL RESULT
          //
          // Wait three seconds after the last recognized speech before
          // processing it.
          // -------------------------------------------------------------------

          _silenceTimer = Timer(
            const Duration(seconds: 3),
                () async {
              if (!mounted ||
                  generation != _speechGeneration ||
                  !_isListening ||
                  _isNavigating ||
                  _isProcessingVoiceCommand ||
                  !_isDashboardActive()) {
                return;
              }

              if (_voiceText.trim().isEmpty) {
                return;
              }

              await _processVoiceCommand(
                expectedGeneration: generation,
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint(
        "Unable to start speech recognition: $e",
      );

      // Only update UI if this is still the active session.
      if (!mounted ||
          generation != _speechGeneration) {
        return;
      }

      _stopListeningVisuals();

      _showSnackBar(
        "Unable to start voice recognition.",
        _danger,
      );
    }
  }


// ===========================================================================
// PROCESS VOICE COMMAND
// ===========================================================================

  Future<void> _processVoiceCommand({int? expectedGeneration}) async {
    if (!mounted) return;

    if (_isNavigating || _isProcessingVoiceCommand) {
      return;
    }

    if (!_isListening && _voiceText.trim().isEmpty) {
      return;
    }

    final command = _voiceText.trim();

    if (command.isEmpty) {
      return;
    }

    // Ignore callbacks from an older recognition session.
    if (expectedGeneration != null &&
        expectedGeneration != _speechGeneration) {
      return;
    }

    // Capture the generation BEFORE stopping the microphone.
    //
    // IMPORTANT:
    // We must NOT invalidate this command here because this is the
    // command we are currently processing.
    final int commandGeneration = _speechGeneration;

    _isProcessingVoiceCommand = true;

    // Stop the microphone physically, but DO NOT invalidate the
    // command currently being processed.
    await _stopSpeechOnly();

    try {
      final intentData =
      await interpretVoiceCommandOffline(command);

      if (!mounted) return;

      // If another navigation/action invalidated this command while
      // interpretation was running, ignore it.
      if (_isNavigating ||
          commandGeneration != _speechGeneration) {
        return;
      }

      await _handleVoiceIntent(
        intentData,
        expectedGeneration: commandGeneration,
      );
    } catch (e) {
      debugPrint(
        'Voice command processing error: $e',
      );
    } finally {
      _isProcessingVoiceCommand = false;
    }
  }

  Future<void> _stopSpeechOnly() async {
    _silenceTimer?.cancel();

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint(
        'Speech stop error: $e',
      );
    }

    _micAnimationController.stop();
    _pulseAnimationController.stop();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }



// ===========================================================================
// HANDLE SPEECH FINISHED
// ===========================================================================

  Future<void> _handleSpeechFinished() async {
    if (!mounted) return;

    if (_isNavigating ||
        _isProcessingVoiceCommand) {
      return;
    }

    if (_voiceText.trim().isNotEmpty) {
      await _processVoiceCommand(
        expectedGeneration: _speechGeneration,
      );
    } else {
      _stopListeningVisuals();
    }
  }


  // ===========================================================================
  // HANDLE VOICE INTENT
  // ===========================================================================

  Future<void> _handleVoiceIntent(
      Map<String, dynamic> intentData, {
        int? expectedGeneration,
      }) async {
    if (!mounted) return;

    if (_isNavigating) {
      return;
    }

    if (expectedGeneration != null &&
        expectedGeneration != _speechGeneration) {
      return;
    }

    final intent = intentData['intent'];
    final param = intentData['parameter'];

    switch (intent) {
    // =======================================================================
    // FIND PATIENT
    // =======================================================================

      case "find_patient":
        await _searchPatients(
          param?.toString() ?? "",
        );
        break;

    // =======================================================================
    // OPEN DOCUMENTS
    // =======================================================================

      case "open_documents":
        if (_searchResults.isNotEmpty) {
          final patient = _searchResults.first;

          final data =
          patient.data() as Map<String, dynamic>;

          _showDocumentsDialog(data);
        } else {
          _showSnackBar(
            "No patient selected.",
            _warning,
          );
        }
        break;

    // =======================================================================
    // OPEN SINGLE DOCUMENT
    // =======================================================================

      case "open_document":
        if (_searchResults.isEmpty) {
          _showSnackBar(
            "Please find a patient first.",
            _warning,
          );
          return;
        }

        final patient = _searchResults.first;

        final data =
        patient.data() as Map<String, dynamic>;

        final documents =
        _normalizeDocuments(
          data['documents'],
        );

        if (param == null ||
            param.toString().trim().isEmpty) {
          _showDocumentsDialog(data);
          return;
        }

        final searchTerm =
        param.toString().trim().toLowerCase();

        final matchedDoc =
        documents.firstWhere(
              (doc) {
            final fileName =
                doc['fileName']
                    ?.toString()
                    .toLowerCase() ??
                    '';

            return fileName.contains(searchTerm);
          },
          orElse: () => <String, dynamic>{},
        );

        if (matchedDoc.isNotEmpty) {
          _openDocument(
            context,
            matchedDoc['fileUrl']?.toString(),
            fileType:
            matchedDoc['fileType']?.toString(),
          );
        } else {
          _showSnackBar(
            'No document found matching "$param"',
            _warning,
          );
        }

        break;

    // =======================================================================
    // SHOW ALL PATIENTS
    // =======================================================================

      case "show_all_patients":
        final snapshot =
        await FirebaseFirestore.instance
            .collection('patients')
            .get();

        if (!mounted || _isNavigating) return;

        setState(() {
          _searchResults = snapshot.docs;
        });

        _showSnackBar(
          "Showing all patients.",
          _primaryDark,
        );

        break;

    // =======================================================================
    // PROFILE
    // =======================================================================

      case "view_profile":
        if (!mounted || _isNavigating) return;

        _tabController.animateTo(2);
        break;

    // =======================================================================
    // BACK
    // =======================================================================

      case "go_back":
        if (!mounted || _isNavigating) return;

        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        break;

    // =======================================================================
    // LOGOUT
    // =======================================================================

      case "logout":
        await _logout();
        break;

    // =======================================================================
    // MEDICAL SEARCH
    // =======================================================================

      case "search_medical":
        if (param == null ||
            param.toString().trim().isEmpty) {
          _showSnackBar(
            "Please say a procedure name.",
            _warning,
          );
          return;
        }

        _showSnackBar(
          "Identifying medical procedure...",
          _primaryDark,
        );

        final correctedTerm =
        await _getClosestMedicalTerm(
          param.toString(),
        );

        if (!mounted || _isNavigating) return;

        if (correctedTerm == null ||
            correctedTerm.isEmpty) {
          _showSnackBar(
            "Couldn't identify the medical procedure: $param",
            _danger,
          );
          return;
        }

        _showSnackBar(
          "Fetching details for: $correctedTerm",
          _primaryDark,
        );

        _isNavigating = true;

        // Invalidate any OLD speech callbacks.
        ++_speechGeneration;

        await _stopSpeechOnly();

        if (!mounted) return;

        try {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ProcedureSummaryPage(
                    procedureName: correctedTerm,
                  ),
            ),
          );
        } finally {
          if (mounted) {
            _isNavigating = false;

            // Start a completely new speech generation after returning.
            ++_speechGeneration;

            setState(() {
              _voiceText = '';
              _isListening = false;
            });
          }
        }

        break;

      default:
        _showSnackBar(
          "Command not recognized.",
          _warning,
        );
    }
  }

  // ===========================================================================
  // STOP MICROPHONE
  // ===========================================================================


  void _stopListeningVisuals() {
    _micAnimationController.stop();
    _pulseAnimationController.stop();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }



// ===========================================================================
// STOP LISTENING
// ===========================================================================

  Future<void> _stopListening() async {
    // -------------------------------------------------------------------------
    // Invalidate the current recognition session.
    // -------------------------------------------------------------------------

    ++_speechGeneration;

    _silenceTimer?.cancel();
    _silenceTimer = null;

    try {
      await _speech.stop();
    } catch (_) {}

    _stopListeningVisuals();
  }

  // ===========================================================================
// STOP MICROPHONE
// ===========================================================================
//
// This is the central microphone shutdown method.
//
// Every call invalidates the previous speech-recognition generation.
//
// Therefore:
//
// old callback
//      ↓
// generation = 4
//
// stopMic()
//      ↓
// generation = 5
//
// old callback sees:
// 4 != 5
//
// and immediately exits.
//
// ===========================================================================

  void stopMic() {
    // Invalidate callbacks from the current recognition session.
    ++_speechGeneration;

    _silenceTimer?.cancel();

    try {
      _speech.stop();
      _speech.cancel();
    } catch (_) {}

    _micAnimationController.stop();
    _pulseAnimationController.stop();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }
  // ===========================================================================
  // PATIENT SEARCH
  // ===========================================================================

// ===========================================================================
// PATIENT SEARCH
// ===========================================================================

  Future<void> _searchPatients(
      String queryText,
      ) async {
    if (!mounted) return;

    if (_isNavigating) {
      return;
    }

    if (queryText.trim().isEmpty) {
      _showSnackBar(
        "Please say a patient ID or name.",
        _warning,
      );
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final firestore =
          FirebaseFirestore.instance;

      // =======================================================================
      // NORMALIZE VOICE INPUT
      // =======================================================================

      String query =
      queryText.trim().toLowerCase();

      query =
          query.replaceAll(
            "patient",
            "",
          ).trim();

      const numMap = {
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "four": "4",
        "five": "5",
        "six": "6",
        "seven": "7",
        "eight": "8",
        "nine": "9",
      };

      for (final entry in numMap.entries) {
        query = query.replaceAll(
          entry.key,
          entry.value,
        );
      }

      query = query
          .replaceAll(
        RegExp(r"\s+"),
        " ",
      )
          .trim();

      // =======================================================================
      // PATIENT ID NORMALIZATION
      //
      // Examples:
      // 9       -> P 009
      // P9      -> P 009
      // P 9     -> P 009
      // P20     -> P 020
      // patient 20 -> P 020
      // =======================================================================

      if (query.startsWith("p")) {
        final digits =
        query.replaceAll(
          RegExp(r"[^0-9]"),
          "",
        );

        if (digits.isNotEmpty) {
          final padded =
          digits.padLeft(3, '0');

          query = "P $padded";
        }
      } else if (RegExp(
        r'^\d{1,3}$',
      ).hasMatch(query)) {
        query =
        "P ${query.padLeft(3, '0')}";
      }

      debugPrint(
        '🔎 Searching patient with normalized query: $query',
      );

      // =======================================================================
      // SEARCH BY PATIENT ID
      // =======================================================================

      final idQuery =
      await firestore
          .collection('patients')
          .where(
        'patientId',
        isEqualTo:
        query.toUpperCase(),
      )
          .get();

      List<DocumentSnapshot> patients =
          idQuery.docs;

      // =======================================================================
      // SEARCH BY searchName ARRAY
      // =======================================================================

      if (patients.isEmpty) {
        final nameQuery =
        await firestore
            .collection('patients')
            .where(
          'searchName',
          arrayContains:
          query.toLowerCase(),
        )
            .get();

        patients = nameQuery.docs;
      }

      // =======================================================================
      // FALLBACK NAME SEARCH
      // =======================================================================

      if (patients.isEmpty) {
        final fallbackQuery =
        await firestore
            .collection('patients')
            .where(
          'name',
          isGreaterThanOrEqualTo:
          query,
        )
            .where(
          'name',
          isLessThanOrEqualTo:
          '$query\uf8ff',
        )
            .get();

        patients = fallbackQuery.docs;
      }

      // =======================================================================
      // VERIFY COMMAND IS STILL VALID
      // =======================================================================

      if (!mounted) return;

      // =======================================================================
      // NO PATIENT
      // =======================================================================

      if (patients.isEmpty) {
        setState(() {
          _isSearching = false;
        });

        _showSnackBar(
          'No patient found for "$queryText"',
          _warning,
        );

        return;
      }

      // =======================================================================
      // PATIENT FOUND
      // =======================================================================

      final foundPatient =
          patients.first;

      final patientData =
      foundPatient.data()
      as Map<String, dynamic>;

      setState(() {
        _searchResults = patients;
        _isSearching = false;
      });

      debugPrint(
        '✅ Patient found: '
            '${patientData['patientId']} '
            '${patientData['name']}',
      );

      // =======================================================================
      // CRITICAL NAVIGATION LOCK
      //
      // Lock BEFORE Navigator.push().
      // This prevents another speech callback from opening the page again.
      // =======================================================================

      if (_isNavigating) {
        return;
      }

      _isNavigating = true;

      // Invalidate all OLD speech callbacks.
      //
      // This happens AFTER the patient has been found, not before.
      ++_speechGeneration;

      await _stopSpeechOnly();

      if (!mounted) return;

      try {
        debugPrint(
          '➡️ Opening PatientHistoryPage for '
              '${patientData['patientId']}',
        );

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PatientHistoryPage(
                  patientId:
                  foundPatient.id,
                  patientData:
                  patientData,
                ),
          ),
        );
      } finally {
        if (mounted) {
          _isNavigating = false;

          // New speech generation for any future interaction.
          ++_speechGeneration;

          setState(() {
            _voiceText = '';
            _isListening = false;
          });
        }
      }
    } catch (e) {
      debugPrint(
        "Patient search error: $e",
      );

      if (mounted) {
        setState(() {
          _isSearching = false;
        });

        _showSnackBar(
          "Unable to search patients.",
          _danger,
        );
      }
    }
  }
  // ===========================================================================
  // DOCUMENT NORMALIZATION
  // ===========================================================================

  List<Map<String, dynamic>> _normalizeDocuments(
      dynamic rawDocuments) {
    if (rawDocuments is! List) {
      return [];
    }

    return rawDocuments.map<Map<String, dynamic>>((item) {
      if (item is Map) {
        return Map<String, dynamic>.from(item);
      }

      return {
        'fileName': item.toString(),
        'fileUrl': '',
        'fileType': '',
      };
    }).toList();
  }

  // ===========================================================================
  // OPEN DOCUMENT
  // ===========================================================================

// ===========================================================================
// OPEN DOCUMENT
// ===========================================================================

  void _openDocument(
      BuildContext context,
      String? url, {
        String? fileType,
      }) {
    if (url == null || url.isEmpty) {
      _showSnackBar(
        "No URL available for this file.",
        _warning,
      );
      return;
    }

    final lowerUrl =
    url.toLowerCase();

    final isPdf =
        fileType?.toLowerCase() == 'pdf' ||
            lowerUrl.contains('.pdf');

    if (!isPdf) {
      _showSnackBar(
        "This file type cannot be previewed here.",
        _warning,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // Lock dashboard speech lifecycle while PDF viewer is displayed.
    // -------------------------------------------------------------------------

    if (_isNavigating) {
      return;
    }

    _isNavigating = true;

    ++_speechGeneration;

    stopMic();

    _voiceText = '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PDFViewerPage(
          pdfUrl: url,
        ),
      ),
    ).whenComplete(() {
      if (!mounted) {
        return;
      }

      _isNavigating = false;

      ++_speechGeneration;

      _silenceTimer?.cancel();
      _silenceTimer = null;

      _voiceText = '';

      setState(() {
        _isListening = false;
      });
    });
  }

  // ===========================================================================
  // DOCUMENT DIALOG
  // ===========================================================================

  void _showDocumentsDialog(
      Map<String, dynamic> data) {
    final documents =
    _normalizeDocuments(data['documents']);

    if (documents.isEmpty) {
      _showSnackBar(
        "No documents available.",
        _warning,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 620,
              maxHeight: 620,
            ),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.10),
                          borderRadius:
                          BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.folder_copy_outlined,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Patient Documents",
                              style: GoogleFonts.inter(
                                color: _textPrimary,
                                fontSize: 20,
                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "${documents.length} document${documents.length == 1 ? '' : 's'} available",
                              style: GoogleFonts.inter(
                                color: _textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: ListView.separated(
                      itemCount: documents.length,
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                      itemBuilder:
                          (context, index) {
                        final document =
                        documents[index];

                        final fileName =
                            document['fileName']
                                ?.toString() ??
                                'Document ${index + 1}';

                        final fileType =
                            document['fileType']
                                ?.toString()
                                .toUpperCase() ??
                                'FILE';

                        final fileUrl =
                            document['fileUrl']
                                ?.toString() ??
                                '';

                        return Material(
                          color: _surfaceLight,
                          borderRadius:
                          BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius:
                            BorderRadius.circular(16),
                            onTap: fileUrl.isEmpty
                                ? null
                                : () {
                              Navigator.pop(
                                  dialogContext);

                              _openDocument(
                                context,
                                fileUrl,
                                fileType:
                                fileType,
                              );
                            },
                            child: Padding(
                              padding:
                              const EdgeInsets.all(
                                  14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration:
                                    BoxDecoration(
                                      color: _danger
                                          .withOpacity(
                                          0.10),
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                          13),
                                    ),
                                    child: Icon(
                                      fileType == 'PDF'
                                          ? Icons
                                          .picture_as_pdf_outlined
                                          : Icons
                                          .description_outlined,
                                      color:
                                      fileType == 'PDF'
                                          ? _danger
                                          : _primary,
                                    ),
                                  ),
                                  const SizedBox(
                                      width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        Text(
                                          fileName,
                                          maxLines: 1,
                                          overflow:
                                          TextOverflow
                                              .ellipsis,
                                          style:
                                          GoogleFonts
                                              .inter(
                                            color:
                                            _textPrimary,
                                            fontWeight:
                                            FontWeight
                                                .w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(
                                            height: 4),
                                        Text(
                                          fileType,
                                          style:
                                          GoogleFonts
                                              .inter(
                                            color:
                                            _textMuted,
                                            fontSize: 11,
                                            fontWeight:
                                            FontWeight
                                                .w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    fileUrl.isEmpty
                                        ? Icons
                                        .block_outlined
                                        : Icons
                                        .arrow_forward_ios_rounded,
                                    size: 15,
                                    color:
                                    _textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

// ===========================================================================
// LOGOUT
// ===========================================================================

  Future<void> _logout() async {
    // -------------------------------------------------------------------------
    // Lock the entire dashboard before signing out.
    // -------------------------------------------------------------------------

    if (_isNavigating) {
      return;
    }

    _isNavigating = true;

    // Invalidate all speech callbacks.
    ++_speechGeneration;

    // Completely shut down recognition.
    stopMic();

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginPage(),
        ),
            (route) => false,
      );
    } catch (e) {
      debugPrint(
        "Logout error: $e",
      );

      if (mounted) {
        _isNavigating = false;

        _showSnackBar(
          "Unable to logout.",
          _danger,
        );
      }
    }
  }
  // ===========================================================================
  // SNACKBAR
  // ===========================================================================

  void _showSnackBar(
      String message,
      Color color,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                color == _danger
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  // ===========================================================================
  // BACKGROUND
  // ===========================================================================

  Widget _buildBackground({
    required Widget child,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF06131F),
            Color(0xFF081A2A),
            Color(0xFF0B2438),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            right: -120,
            child: AnimatedBuilder(
              animation: _floatingAnimationController,
              builder: (_, child) {
                final double verticalOffset =
                    _floatingAnimationController.value * 25.0;

                return Transform.translate(
                  offset: Offset(
                    0,
                    verticalOffset,
                  ),
                  child: child,
                );
              },
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primary.withOpacity(0.035),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -140,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryDark.withOpacity(0.045),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  // ===========================================================================
  // GLASS CARD
  // ===========================================================================

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding =
    const EdgeInsets.all(20),
    double radius = 22,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withOpacity(0.075),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  // ===========================================================================
  // SECTION HEADER
  // ===========================================================================

  Widget _sectionHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: GoogleFonts.inter(
                  color: _primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: _textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ===========================================================================
  // VOICE ASSISTANT PAGE
  // ===========================================================================

  Widget _buildVoiceAssistant() {
    final width = MediaQuery.of(context).size.width;

    return _buildBackground(
      child: FadeTransition(
        opacity: _pageFadeAnimation,
        child: SlideTransition(
          position: _pageSlideAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: width > 1000 ? 44 : 20,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(maxWidth: 1250),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      eyebrow: "SURGIASSIST CLINICAL AI",
                      title: "Voice Assistant",
                      subtitle:
                      "Hands-free access to patient information and clinical workflows.",
                      trailing: _buildOnlineStatus(),
                    ),
                    const SizedBox(height: 26),

                    // ---------------------------------------------------------
                    // VOICE HERO
                    // ---------------------------------------------------------

                    _buildVoiceHero(),

                    // ---------------------------------------------------------
                    // QUICK COMMANDS REMOVED
                    // ---------------------------------------------------------

                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      _buildVoiceSearchResults(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ONLINE STATUS
  // ===========================================================================

  Widget _buildOnlineStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: _success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _success.withOpacity(0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _success,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "SYSTEM READY",
            style: GoogleFonts.inter(
              color: _success,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // VOICE HERO
  // ===========================================================================

  Widget _buildVoiceHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 760;

        return _glassCard(
          padding: EdgeInsets.all(
            compact ? 24 : 34,
          ),
          radius: 28,
          child: compact
              ? Column(
            children: [
              _buildMicOrb(),
              const SizedBox(height: 26),
              _buildVoiceTextPanel(),
            ],
          )
              : Row(
            children: [
              Expanded(
                flex: 5,
                child: _buildMicOrb(),
              ),
              const SizedBox(width: 34),
              Expanded(
                flex: 6,
                child: _buildVoiceTextPanel(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // MICROPHONE ORB
  // ===========================================================================

  Widget _buildMicOrb() {
    return SizedBox(
      height: 300,
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _micAnimationController,
            _pulseAnimationController,
          ]),
          builder: (context, child) {
            final double pulse = _isListening
                ? 1.0 +
                (_pulseAnimationController.value * 0.08)
                : 1.0;

            final double outerPulse = 0.85 +
                (_pulseAnimationController.value * 0.15);

            final double innerPulse = 0.90 +
                (_pulseAnimationController.value * 0.10);

            return Stack(
              alignment: Alignment.center,
              children: [
                if (_isListening)
                  Container(
                    width: 250.0 * outerPulse,
                    height: 250.0 * outerPulse,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                        _primary.withOpacity(0.10),
                        width: 1,
                      ),
                    ),
                  ),

                if (_isListening)
                  Container(
                    width: 205.0 * innerPulse,
                    height: 205.0 * innerPulse,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                        _primary.withOpacity(0.16),
                        width: 1,
                      ),
                    ),
                  ),

                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _primary.withOpacity(
                            _isListening
                                ? 0.28
                                : 0.16,
                          ),
                          _primaryDark.withOpacity(
                            0.10,
                          ),
                        ],
                      ),
                      border: Border.all(
                        color:
                        _primary.withOpacity(0.32),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                          _primary.withOpacity(
                            _isListening
                                ? 0.22
                                : 0.08,
                          ),
                          blurRadius:
                          _isListening
                              ? 45
                              : 25,
                          spreadRadius:
                          _isListening
                              ? 8
                              : 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isListening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: _primary,
                        size: 54,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // VOICE TEXT PANEL
  // ===========================================================================

  Widget _buildVoiceTextPanel() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _isListening
                    ? _success
                    : _textMuted,
                shape: BoxShape.circle,
                boxShadow: _isListening
                    ? [
                  BoxShadow(
                    color: _success
                        .withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ]
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _isListening
                    ? "LISTENING FOR COMMAND"
                    : "VOICE ASSISTANT READY",
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _isListening
                      ? _success
                      : _textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          _isListening
              ? "I'm listening..."
              : "How can I assist?",
          style: GoogleFonts.inter(
            color: _textPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _voiceText.isEmpty
              ? "Use your voice to find patients, open documents, access your profile, or look up surgical procedures."
              : _voiceText,
          style: GoogleFonts.inter(
            color: _voiceText.isEmpty
                ? _textSecondary
                : _primary,
            fontSize: 15,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isListening
                      ? _stopListening
                      : _startListening,
                  icon: Icon(
                    _isListening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _isListening
                        ? "Stop Listening"
                        : "Start Voice Command",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: _background,
                    elevation: 0,
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(15),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          "Voice recognition works best in a quiet operating environment.",
          style: GoogleFonts.inter(
            color: _textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // VOICE SEARCH RESULTS
  // ===========================================================================

  Widget _buildVoiceSearchResults() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          "SEARCH RESULTS",
          style: GoogleFonts.inter(
            color: _primary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ..._searchResults
            .take(3)
            .map(_buildPatientCard),
      ],
    );
  }

  // ===========================================================================
  // PATIENTS PAGE
  // ===========================================================================

  Widget _buildPatientsPage() {
    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    return _buildBackground(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('patients')
            .where(
          'assignedDoctor',
          isEqualTo: uid,
        )
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(
              "Unable to load patients",
              snapshot.error.toString(),
            );
          }

          if (!snapshot.hasData) {
            return _buildLoadingState(
              "Loading patient records...",
            );
          }

          final patients =
              snapshot.data!.docs;

          final filteredPatients =
          patients.where((doc) {
            if (_patientSearchText
                .trim()
                .isEmpty) {
              return true;
            }

            final data =
            doc.data() as Map<String, dynamic>;

            final query =
            _patientSearchText.toLowerCase();

            final name =
                data['name']
                    ?.toString()
                    .toLowerCase() ??
                    '';

            final patientId =
                data['patientId']
                    ?.toString()
                    .toLowerCase() ??
                    '';

            return name.contains(query) ||
                patientId.contains(query);
          }).toList();

          return SingleChildScrollView(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 1250,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      eyebrow:
                      "PATIENT MANAGEMENT",
                      title: "My Patients",
                      subtitle:
                      "Review assigned patients and access their clinical records.",
                    ),
                    const SizedBox(height: 24),
                    _buildPatientStats(
                      patients,
                    ),
                    const SizedBox(height: 20),
                    _buildPatientSearch(),
                    const SizedBox(height: 20),
                    if (filteredPatients.isEmpty)
                      _buildEmptyPatients()
                    else
                      ...filteredPatients.map(
                        _buildPatientCard,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PATIENT STATS
  // ===========================================================================

// ===========================================================================
// PATIENT KPI STATS
// ===========================================================================

  Widget _buildPatientStats(
      List<QueryDocumentSnapshot> patients) {
    int documentCount = 0;

    for (final patient in patients) {
      final data =
      patient.data() as Map<String, dynamic>;

      final docs =
      _normalizeDocuments(data['documents']);

      documentCount += docs.length;
    }

    final cards = [
      (
      "Patients",
      patients.length.toString(),
      Icons.groups_2_outlined,
      _primary,
      ),
      (
      "Documents",
      documentCount.toString(),
      Icons.folder_copy_outlined,
      _teal,
      ),
      (
      "Status",
      "Active",
      Icons.verified_outlined,
      _success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        return Row(
          children: List.generate(
            cards.length,
                (index) {
              final card = cards[index];

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == cards.length - 1 ? 0 : 10,
                  ),
                  child: _buildCompactKpiCard(
                    title: card.$1,
                    value: card.$2,
                    icon: card.$3,
                    color: card.$4,
                    compact: isCompact,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }


// ===========================================================================
// COMPACT KPI CARD
// ===========================================================================

  Widget _buildCompactKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      height: compact ? 78 : 88,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // -------------------------------------------------------------------
          // ICON
          // -------------------------------------------------------------------

          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: compact ? 18 : 20,
            ),
          ),

          const SizedBox(width: 10),

          // -------------------------------------------------------------------
          // KPI VALUE + LABEL
          // -------------------------------------------------------------------

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontSize: compact ? 17 : 19,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _textMuted,
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
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
  // STAT CARD
  // ===========================================================================

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _glassCard(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 15,
      ),
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color:
              color.withOpacity(0.10),
              borderRadius:
              BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: _textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight:
                    FontWeight.w700,
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
  // PATIENT SEARCH
  // ===========================================================================

  Widget _buildPatientSearch() {
    return _glassCard(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 5,
      ),
      radius: 17,
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: _textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller:
              _patientSearchController,
              onChanged: (value) {
                setState(() {
                  _patientSearchText =
                      value;
                });
              },
              style: GoogleFonts.inter(
                color: _textPrimary,
                fontSize: 13,
              ),
              decoration:
              InputDecoration(
                hintText:
                "Search by patient name or ID...",
                hintStyle:
                GoogleFonts.inter(
                  color: _textMuted,
                  fontSize: 13,
                ),
                border:
                InputBorder.none,
              ),
            ),
          ),
          if (_patientSearchText.isNotEmpty)
            IconButton(
              onPressed: () {
                _patientSearchController
                    .clear();

                setState(() {
                  _patientSearchText = '';
                });
              },
              icon: const Icon(
                Icons.close_rounded,
                color: _textMuted,
                size: 19,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EMPTY PATIENT STATE
  // ===========================================================================

  Widget _buildEmptyPatients() {
    return _glassCard(
      padding:
      const EdgeInsets.symmetric(
        vertical: 60,
        horizontal: 30,
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color:
                _primary.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons
                    .person_search_outlined,
                color: _primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _patientSearchText.isEmpty
                  ? "No patients assigned"
                  : "No matching patients",
              style: GoogleFonts.inter(
                color: _textPrimary,
                fontWeight:
                FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _patientSearchText.isEmpty
                  ? "Assigned patient records will appear here."
                  : "Try searching with another name or patient ID.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PATIENT CARD
  // ===========================================================================

  Widget _buildPatientCard(
      DocumentSnapshot doc) {
    final data =
    doc.data() as Map<String, dynamic>;

    final patientId =
        data['patientId']?.toString() ??
            doc.id;

    final name =
        data['name']?.toString() ??
            'Unknown Patient';

    final age =
        data['age']?.toString() ??
            'N/A';

    final gender =
        data['gender']?.toString() ??
            'N/A';

    final doctor =
        data['assignedDoctor']
            ?.toString() ??
            'Assigned';

    final documents =
    _normalizeDocuments(
        data['documents']);

    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 12,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(20),
          onTap: () async {
            // -------------------------------------------------------------------------
            // Prevent double taps from opening multiple PatientHistoryPage instances.
            // -------------------------------------------------------------------------

            if (_isNavigating) {
              return;
            }

            // -------------------------------------------------------------------------
            // Lock navigation BEFORE stopping the microphone.
            // -------------------------------------------------------------------------

            _isNavigating = true;

            // Invalidate every active speech callback.
            ++_speechGeneration;

            // Stop microphone completely.
            stopMic();

            // Prevent the previous command from being processed again.
            _voiceText = '';

            debugPrint(
              '➡️ Opening PatientHistoryPage manually for ${doc.id}',
            );

            try {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PatientHistoryPage(
                        patientId: doc.id,
                        patientData: data,
                      ),
                ),
              );
            } finally {
              if (mounted) {
                _isNavigating = false;

                // A completely fresh speech session must be used if the surgeon
                // explicitly starts voice recognition again.
                ++_speechGeneration;

                _silenceTimer?.cancel();
                _silenceTimer = null;

                _voiceText = '';

                setState(() {
                  _isListening = false;
                });

                debugPrint(
                  '⬅️ Returned from PatientHistoryPage.',
                );
              }
            }
          },
          child: Ink(
            decoration:
            BoxDecoration(
              color: Colors.white
                  .withOpacity(0.045),
              borderRadius:
              BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white
                    .withOpacity(0.065),
              ),
            ),
            child: Padding(
              padding:
              const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration:
                    BoxDecoration(
                      gradient:
                      const LinearGradient(
                        colors: [
                          _primaryDark,
                          _primary,
                        ],
                        begin:
                        Alignment.topLeft,
                        end: Alignment
                            .bottomRight,
                      ),
                      borderRadius:
                      BorderRadius
                          .circular(16),
                    ),
                    child: const Icon(
                      Icons
                          .person_outline_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          GoogleFonts.inter(
                            color:
                            _textPrimary,
                            fontSize: 15,
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                        const SizedBox(
                            height: 7),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _infoChip(
                              Icons
                                  .badge_outlined,
                              patientId,
                              _primary,
                            ),
                            _infoChip(
                              Icons
                                  .calendar_today_outlined,
                              "Age $age",
                              _textSecondary,
                            ),
                            _infoChip(
                              Icons.wc_outlined,
                              gender,
                              _textSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(
                            height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons
                                  .medical_services_outlined,
                              color:
                              _textMuted,
                              size: 13,
                            ),
                            const SizedBox(
                                width: 5),
                            Expanded(
                              child: Text(
                                "Doctor: $doctor",
                                maxLines: 1,
                                overflow:
                                TextOverflow
                                    .ellipsis,
                                style:
                                GoogleFonts
                                    .inter(
                                  color:
                                  _textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration:
                        BoxDecoration(
                          color: _primary
                              .withOpacity(
                              0.07),
                          borderRadius:
                          BorderRadius
                              .circular(
                              10),
                        ),
                        child: Row(
                          mainAxisSize:
                          MainAxisSize
                              .min,
                          children: [
                            const Icon(
                              Icons
                                  .folder_outlined,
                              color:
                              _primary,
                              size: 14,
                            ),
                            const SizedBox(
                                width: 5),
                            Text(
                              documents.length
                                  .toString(),
                              style:
                              GoogleFonts
                                  .inter(
                                color:
                                _primary,
                                fontSize: 11,
                                fontWeight:
                                FontWeight
                                    .w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                          height: 9),
                      Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                            "Documents",
                            onPressed:
                            documents
                                .isEmpty
                                ? null
                                : () {
                              _showDocumentsDialog(
                                  data);
                            },
                            icon:
                            const Icon(
                              Icons
                                  .folder_open_outlined,
                              color:
                              _primary,
                              size: 20,
                            ),
                          ),
                          const Icon(
                            Icons
                                .arrow_forward_ios_rounded,
                            color:
                            _textMuted,
                            size: 14,
                          ),
                        ],
                      ),
                    ],
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
  // INFO CHIP
  // ===========================================================================

  Widget _infoChip(
      IconData icon,
      String text,
      Color color,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius:
        BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PROFILE PAGE
  // ===========================================================================

  Widget _buildSettings() {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _buildErrorState(
        "Session unavailable",
        "Please sign in again.",
      );
    }

    final userDoc =
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    return _buildBackground(
      child: StreamBuilder<DocumentSnapshot>(
        stream: userDoc.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(
              "Unable to load profile",
              snapshot.error.toString(),
            );
          }

          if (!snapshot.hasData) {
            return _buildLoadingState(
              "Loading surgeon profile...",
            );
          }

          final data =
              snapshot.data!.data()
              as Map<String, dynamic>? ??
                  {};

          final name =
              data['name'] ??
                  user.displayName ??
                  'Surgeon';

          final email =
              data['email'] ??
                  user.email ??
                  'N/A';

          final role =
              data['role'] ??
                  'surgeon';

          final photoUrl =
              data['photoUrl'] ?? '';

          return SingleChildScrollView(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 1050,
                ),
                child: Column(
                  children: [
                    _buildProfileHero(
                      name.toString(),
                      email.toString(),
                      role.toString(),
                      photoUrl.toString(),
                    ),
                    const SizedBox(height: 18),
                    _buildProfileActions(
                      userDoc,
                      name.toString(),
                      photoUrl.toString(),
                    ),
                    const SizedBox(height: 18),
                    _buildSecurityCard(user),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PROFILE HERO
  // ===========================================================================

  Widget _buildProfileHero(
      String name,
      String email,
      String role,
      String photoUrl,
      ) {
    return _glassCard(
      padding:
      const EdgeInsets.all(28),
      radius: 26,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 600;

          final avatar = Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
              _primary.withOpacity(0.10),
              border: Border.all(
                color:
                _primary.withOpacity(0.28),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: photoUrl.isNotEmpty
                  ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) =>
                const Icon(
                  Icons
                      .person_outline_rounded,
                  color: _primary,
                  size: 42,
                ),
              )
                  : const Icon(
                Icons
                    .person_outline_rounded,
                color: _primary,
                size: 42,
              ),
            ),
          );

          final information =
          Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                  _primary.withOpacity(
                      0.08),
                  borderRadius:
                  BorderRadius.circular(
                      8),
                ),
                child: Text(
                  role.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: _primary,
                    fontSize: 9,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: GoogleFonts.inter(
                  color: _textPrimary,
                  fontSize: 25,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                email,
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Center(child: avatar),
                const SizedBox(height: 20),
                information,
              ],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 22),
              Expanded(
                child: information,
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PROFILE ACTIONS
  // ===========================================================================

  Widget _buildProfileActions(
      DocumentReference userDoc,
      String name,
      String photoUrl,
      ) {
    return _glassCard(
      padding:
      const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            "PROFILE SETTINGS",
            style: GoogleFonts.inter(
              color: _primary,
              fontSize: 10,
              fontWeight:
              FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          _settingsTile(
            icon: Icons.edit_outlined,
            title: "Edit profile",
            subtitle:
            "Update your name and profile photo.",
            onTap: () {
              _showEditProfileDialog(
                context,
                userDoc,
                TextEditingController(
                  text: name,
                ),
                photoUrl,
              );
            },
          ),
          const SizedBox(height: 10),
          _settingsTile(
            icon:
            Icons.lock_outline_rounded,
            title: "Change password",
            subtitle:
            "Update your account password securely.",
            onTap: () {
              _showChangePasswordDialog(
                context,
                TextEditingController(),
                TextEditingController(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SETTINGS TILE
  // ===========================================================================

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(16),
        child: Ink(
          padding:
          const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: _surfaceLight,
            borderRadius:
            BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                BoxDecoration(
                  color: _primary
                      .withOpacity(0.08),
                  borderRadius:
                  BorderRadius.circular(
                      12),
                ),
                child: Icon(
                  icon,
                  color: _primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      title,
                      style:
                      GoogleFonts.inter(
                        color:
                        _textPrimary,
                        fontSize: 13,
                        fontWeight:
                        FontWeight
                            .w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style:
                      GoogleFonts.inter(
                        color:
                        _textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons
                    .arrow_forward_ios_rounded,
                color: _textMuted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECURITY CARD
  // ===========================================================================

  Widget _buildSecurityCard(User user) {
    return _glassCard(
      padding:
      const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            "ACCOUNT SECURITY",
            style: GoogleFonts.inter(
              color: _primary,
              fontSize: 10,
              fontWeight:
              FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(
                Icons
                    .verified_user_outlined,
                color: _success,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      "Authenticated account",
                      style:
                      GoogleFonts.inter(
                        color:
                        _textPrimary,
                        fontSize: 13,
                        fontWeight:
                        FontWeight
                            .w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email ??
                          "No email",
                      style:
                      GoogleFonts.inter(
                        color:
                        _textMuted,
                        fontSize: 11,
                      ),
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
                      .withOpacity(0.08),
                  borderRadius:
                  BorderRadius.circular(
                      8),
                ),
                child: Text(
                  "SECURE",
                  style: GoogleFonts.inter(
                    color: _success,
                    fontSize: 9,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(
                Icons.logout_rounded,
                size: 19,
              ),
              label: const Text(
                "Sign out",
              ),
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                _danger,
                side: BorderSide(
                  color: _danger
                      .withOpacity(0.35),
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                      14),
                ),
                textStyle:
                GoogleFonts.inter(
                  fontWeight:
                  FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EDIT PROFILE DIALOG
  // ===========================================================================

  void _showEditProfileDialog(
      BuildContext context,
      DocumentReference userDoc,
      TextEditingController nameController,
      String currentPhotoUrl,
      ) {
    final photoController =
    TextEditingController(
      text: currentPhotoUrl,
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _buildDialog(
          title: "Edit Profile",
          icon: Icons.edit_outlined,
          content: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              _buildDialogTextField(
                controller:
                nameController,
                label: "Full Name",
                icon:
                Icons.person_outline,
              ),
              const SizedBox(height: 14),
              _buildDialogTextField(
                controller:
                photoController,
                label:
                "Profile Photo URL",
                icon:
                Icons.image_outlined,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                      dialogContext),
              child: Text(
                "Cancel",
                style:
                GoogleFonts.inter(
                  color:
                  _textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name =
                nameController.text
                    .trim();

                final photo =
                photoController.text
                    .trim();

                if (name.isEmpty) {
                  _showSnackBar(
                    "Please enter your name.",
                    _warning,
                  );
                  return;
                }

                try {
                  await userDoc.update({
                    'name': name,
                    'photoUrl': photo,
                  });

                  await FirebaseAuth
                      .instance
                      .currentUser!
                      .updateDisplayName(
                      name);

                  await FirebaseAuth
                      .instance
                      .currentUser!
                      .updatePhotoURL(
                      photo);

                  if (!mounted) return;

                  Navigator.pop(
                      dialogContext);

                  _showSnackBar(
                    "Profile updated successfully.",
                    _success,
                  );
                } catch (e) {
                  _showSnackBar(
                    "Unable to update profile.",
                    _danger,
                  );
                }
              },
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                _primary,
                foregroundColor:
                _background,
                elevation: 0,
              ),
              child:
              const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // CHANGE PASSWORD DIALOG
  // ===========================================================================

  void _showChangePasswordDialog(
      BuildContext context,
      TextEditingController
      passwordController,
      TextEditingController
      confirmPasswordController,
      ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return _buildDialog(
          title: "Change Password",
          icon:
          Icons.lock_reset_rounded,
          content: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              _buildDialogTextField(
                controller:
                passwordController,
                label: "New Password",
                icon:
                Icons.lock_outline,
                obscure: true,
              ),
              const SizedBox(height: 14),
              _buildDialogTextField(
                controller:
                confirmPasswordController,
                label:
                "Confirm Password",
                icon: Icons
                    .lock_outline_rounded,
                obscure: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                      dialogContext),
              child: Text(
                "Cancel",
                style:
                GoogleFonts.inter(
                  color:
                  _textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final password =
                passwordController
                    .text
                    .trim();

                final confirm =
                confirmPasswordController
                    .text
                    .trim();

                if (password.isEmpty ||
                    confirm.isEmpty) {
                  _showSnackBar(
                    "Please complete both fields.",
                    _warning,
                  );
                  return;
                }

                if (password != confirm) {
                  _showSnackBar(
                    "Passwords do not match.",
                    _danger,
                  );
                  return;
                }

                if (password.length <
                    6) {
                  _showSnackBar(
                    "Password must contain at least 6 characters.",
                    _warning,
                  );
                  return;
                }

                try {
                  await FirebaseAuth
                      .instance
                      .currentUser!
                      .updatePassword(
                      password);

                  if (!mounted) return;

                  Navigator.pop(
                      dialogContext);

                  _showSnackBar(
                    "Password updated successfully.",
                    _success,
                  );
                } catch (e) {
                  _showSnackBar(
                    "Unable to update password. You may need to sign in again before changing it.",
                    _danger,
                  );
                }
              },
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                _primary,
                foregroundColor:
                _background,
                elevation: 0,
              ),
              child:
              const Text("Update"),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // DIALOG
  // ===========================================================================

  Widget _buildDialog({
    required String title,
    required IconData icon,
    required Widget content,
    required List<Widget> actions,
  }) {
    return Dialog(
      backgroundColor:
      Colors.transparent,
      insetPadding:
      const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 30,
      ),
      child: Container(
        constraints:
        const BoxConstraints(
          maxWidth: 520,
        ),
        padding:
        const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius:
          BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.4),
              blurRadius: 40,
              offset:
              const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration:
                  BoxDecoration(
                    color: _primary
                        .withOpacity(0.09),
                    borderRadius:
                    BorderRadius
                        .circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: _primary,
                  ),
                ),
                const SizedBox(
                    width: 13),
                Expanded(
                  child: Text(
                    title,
                    style:
                    GoogleFonts.inter(
                      color:
                      _textPrimary,
                      fontSize: 19,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
                height: 22),
            content,
            const SizedBox(
                height: 24),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.end,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DIALOG TEXT FIELD
  // ===========================================================================

  Widget _buildDialogTextField({
    required TextEditingController
    controller,
    required String label,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.inter(
        color: _textPrimary,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
        GoogleFonts.inter(
          color: _textSecondary,
          fontSize: 12,
        ),
        prefixIcon: Icon(
          icon,
          color: _textMuted,
          size: 20,
        ),
        filled: true,
        fillColor: _surfaceLight,
        border:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
              14),
          borderSide:
          BorderSide.none,
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
              14),
          borderSide:
          const BorderSide(
            color: _primary,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // LOADING STATE
  // ===========================================================================

  Widget _buildLoadingState(
      String message) {
    return _buildBackground(
      child: Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
                color: _primary,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              message,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR STATE
  // ===========================================================================

  Widget _buildErrorState(
      String title,
      String subtitle,
      ) {
    return _buildBackground(
      child: Center(
        child: Padding(
          padding:
          const EdgeInsets.all(30),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              Container(
                width: 65,
                height: 65,
                decoration:
                BoxDecoration(
                  color: _danger
                      .withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons
                      .error_outline_rounded,
                  color: _danger,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: _textPrimary,
                  fontSize: 17,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign:
                TextAlign.center,
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // APP BAR / HEADER
  //
  // IMPORTANT CHANGES:
  // 1. SafeArea prevents overlap with system status/notification area.
  // 2. TabBar is NOT scrollable.
  // 3. Each tab receives equal width.
  // 4. Header has controlled vertical dimensions.
  // ===========================================================================

  Widget _buildHeader() {
    final user =
        FirebaseAuth.instance.currentUser;

    final displayName =
    user?.displayName?.trim();

    return Material(
      color: _background,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            color:
            _background.withOpacity(
                0.98),
            border: Border(
              bottom: BorderSide(
                color: Colors.white
                    .withOpacity(0.055),
              ),
            ),
          ),
          child: Padding(
            padding:
            const EdgeInsets.fromLTRB(
              24,
              14,
              24,
              8,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                // -------------------------------------------------------------
                // TOP BRAND ROW
                // -------------------------------------------------------------

                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                      BoxDecoration(
                        gradient:
                        const LinearGradient(
                          colors: [
                            _primaryDark,
                            _primary,
                          ],
                          begin:
                          Alignment.topLeft,
                          end: Alignment
                              .bottomRight,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _primary
                                .withOpacity(
                                0.12),
                            blurRadius: 18,
                            offset:
                            const Offset(
                                0, 6),
                          ),
                        ],
                      ),
                      child:
                      const Icon(
                        Icons
                            .medical_services_outlined,
                        color:
                        Colors.white,
                        size: 22,
                      ),
                    ),

                    const SizedBox(
                        width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          Text(
                            "SURGIASSIST",
                            style:
                            GoogleFonts
                                .inter(
                              color:
                              _textPrimary,
                              fontSize: 16,
                              fontWeight:
                              FontWeight
                                  .w800,
                              letterSpacing:
                              1.1,
                            ),
                          ),
                          Text(
                            "SURGEON WORKSTATION",
                            style:
                            GoogleFonts
                                .inter(
                              color:
                              _textMuted,
                              fontSize: 8,
                              fontWeight:
                              FontWeight
                                  .w700,
                              letterSpacing:
                              1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (displayName !=
                        null &&
                        displayName
                            .isNotEmpty)
                      Container(
                        constraints:
                        const BoxConstraints(
                          maxWidth: 220,
                        ),
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration:
                        BoxDecoration(
                          color: Colors
                              .white
                              .withOpacity(
                              0.035),
                          borderRadius:
                          BorderRadius
                              .circular(
                              12),
                          border:
                          Border.all(
                            color: Colors
                                .white
                                .withOpacity(
                                0.045),
                          ),
                        ),
                        child: Row(
                          mainAxisSize:
                          MainAxisSize
                              .min,
                          children: [
                            const Icon(
                              Icons
                                  .person_outline_rounded,
                              color:
                              _primary,
                              size: 16,
                            ),
                            const SizedBox(
                                width: 7),
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow:
                                TextOverflow
                                    .ellipsis,
                                style:
                                GoogleFonts
                                    .inter(
                                  color:
                                  _textSecondary,
                                  fontSize: 11,
                                  fontWeight:
                                  FontWeight
                                      .w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // -------------------------------------------------------------
                // EQUALLY DISTRIBUTED TAB NAVIGATION
                // -------------------------------------------------------------

                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: TabBar(
                    controller:
                    _tabController,

                    // IMPORTANT:
                    // Removed isScrollable: true.
                    // This makes the tabs distribute equally.
                    isScrollable: false,

                    // Each tab gets exactly 1/3 of available width.
                    tabAlignment:
                    TabAlignment.fill,

                    dividerColor:
                    Colors.transparent,

                    indicatorSize:
                    TabBarIndicatorSize.tab,

                    indicatorPadding:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 3,
                      vertical: 3,
                    ),

                    indicator:
                    BoxDecoration(
                      color: _primary
                          .withOpacity(
                          0.09),
                      borderRadius:
                      BorderRadius
                          .circular(
                          12),
                      border:
                      Border.all(
                        color: _primary
                            .withOpacity(
                            0.14),
                      ),
                    ),

                    labelColor:
                    _primary,

                    unselectedLabelColor:
                    _textMuted,

                    labelStyle:
                    GoogleFonts
                        .inter(
                      fontSize: 11,
                      fontWeight:
                      FontWeight.w700,
                    ),

                    unselectedLabelStyle:
                    GoogleFonts
                        .inter(
                      fontSize: 11,
                      fontWeight:
                      FontWeight.w500,
                    ),

                    splashBorderRadius:
                    BorderRadius
                        .circular(
                        12),

                    tabs: const [
                      Tab(
                        icon: Icon(
                          Icons
                              .mic_none_rounded,
                          size: 18,
                        ),
                        text:
                        "Voice Assistant",
                      ),
                      Tab(
                        icon: Icon(
                          Icons
                              .groups_outlined,
                          size: 18,
                        ),
                        text: "Patients",
                      ),
                      Tab(
                        icon: Icon(
                          Icons
                              .person_outline_rounded,
                          size: 18,
                        ),
                        text: "Profile",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,

      // Prevent the Scaffold itself from adding unwanted
      // system-area padding around the dashboard.
      resizeToAvoidBottomInset: true,

      body: Column(
        children: [
          // -------------------------------------------------------------------
          // FIXED SAFE HEADER
          // -------------------------------------------------------------------

          _buildHeader(),

          // -------------------------------------------------------------------
          // PAGE CONTENT
          // -------------------------------------------------------------------

          Expanded(
            child: TabBarView(
              controller:
              _tabController,
              children: [
                _buildVoiceAssistant(),
                _buildPatientsPage(),
                _buildSettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

// ===========================================================================
// DISPOSE
// ===========================================================================

  @override
  void dispose() {
    // -------------------------------------------------------------------------
    // Invalidate every outstanding speech callback.
    // -------------------------------------------------------------------------

    ++_speechGeneration;

    _isNavigating = true;
    _isProcessingVoiceCommand = true;

    _silenceTimer?.cancel();
    _silenceTimer = null;

    try {
      _speech.stop();
      _speech.cancel();
    } catch (_) {}

    _patientSearchController.dispose();

    _tabController.dispose();

    _pageAnimationController.dispose();
    _micAnimationController.dispose();
    _pulseAnimationController.dispose();
    _floatingAnimationController.dispose();

    super.dispose();
  }
}
