import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
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

class _PatientHistoryPageState extends State<PatientHistoryPage> {
  late final stt.SpeechToText _speech;

  /// 🔒 HARD MIC LOCK — once true, mic can NEVER restart on this page
  bool _micLocked = false;

  Timer? _startDelayTimer;
  Timer? _autoStopTimer;

  bool _isListening = false;
  bool _isNavigating = false;
  bool _commandHandled = false;

  bool _micStartedOnce = false; // 🔐 one-shot guard
  bool _micPermanentlyDisabled = false;
  Timer? _micTimer;

  List<dynamic> _documents = [];

  // ================= INIT =================

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    // 🎤 Start mic after page fully stabilizes
    _startDelayTimer = Timer(
      const Duration(seconds: 2),
      _startMic,
    );
  }

  Future<void> _goBackToSurgeonDashboard() async {
    if (_isNavigating) return;
    _isNavigating = true;

    // 🔒 Lock & stop mic safely
    _micLocked = true;
    await _hardStopMic();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SurgeonDashboard()),
          (route) => false, // ❌ remove all previous routes
    );
  }


  // ================= MIC CONTROL =================

  Future<void> _startMic() async {
    if (!mounted || _isListening || _micLocked) return;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint("❌ Microphone permission denied");
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint("🎙️ Status: $status");
        // 🚫 DO NOT restart mic from status callbacks
      },
      onError: (error) {
        debugPrint("❌ Speech error: $error");
        _stopMic();
      },
    );

    if (!available) {
      debugPrint("❌ Speech engine unavailable");
      return;
    }

    debugPrint("✅ MIC STARTED");

    _speech.listen(
      listenFor: const Duration(seconds: 100),
      pauseFor: const Duration(seconds: 4),
      partialResults: false,
      onResult: (result) {
        final spoken = result.recognizedWords.toLowerCase().trim();
        debugPrint("🎤 Heard: $spoken");
        _handleVoiceCommand(spoken);
      },
    );

    _isListening = true;

    _autoStopTimer = Timer(
      const Duration(seconds: 100),
      _stopMic,
    );
  }

  void _stopMic() {
    if (_isListening) {
      debugPrint("⏹️ MIC STOPPED");
      _speech.stop();
      _isListening = false;
    }
  }

  // ================= VOICE COMMAND HANDLER =================

  Future<void> _stopMicCompletely() async {
    _micPermanentlyDisabled = true;
    _micTimer?.cancel();

    try {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}

    debugPrint("⛔ MIC FULLY SHUT DOWN");
  }

  // ================= VOICE COMMAND =================

  void _handleVoiceCommand(String speech) async {
    if (_isNavigating || _documents.isEmpty) return;
    if (!speech.contains('open')) return;

    int index = 0;
    if (speech.contains('two')) index = 1;
    if (speech.contains('three')) index = 2;

    if (index >= _documents.length) return;

    _isNavigating = true;
    await _stopMicCompletely();

    final doc = _documents[index];
    debugPrint("📂 Opening document ${index + 1}");

    if (!mounted) return;

    _openDocument(
      context,
      doc['fileUrl'],
      fileType: doc['fileType'],
    );
  }
  // ================= NAVIGATION =================


  Future<void> _openDocument(
      BuildContext context,
      String? url, {
        String? fileType,
      }) async {
    if (!mounted || url == null || url.isEmpty) return;

    // 🔒 HARD LOCK MIC FOREVER ON THIS PAGE
    _micLocked = true;

    // ✅ ABSOLUTE MIC SHUTDOWN
    await _hardStopMic();

    final isPdf =
        fileType?.toLowerCase() == 'pdf' || url.toLowerCase().contains('.pdf');

    if (isPdf) {
      // ---------- PDF ----------
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PDFViewerPage(pdfUrl: url),
        ),
      );
    } else {
      // ---------- IMAGE CAROUSEL ----------
      final imageUrls = _documents
          .where((d) =>
      (d['fileType'] ?? '').toLowerCase() != 'pdf' &&
          (d['fileUrl'] ?? '').toString().isNotEmpty)
          .map<String>((d) => d['fileUrl'] as String)
          .toList();

      final initialIndex = imageUrls.indexOf(url);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            imageUrls: imageUrls,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
          ),
        ),
      );
    }
  }


  /// ✅ HARD, AWAITABLE MIC STOP
  Future<void> _hardStopMic() async {
    if (!_isListening) return;

    debugPrint("⏹️ MIC STOPPING...");
    _isListening = false;

    await _speech.stop();          // ✅ await engine shutdown
    await Future.delayed(
        const Duration(milliseconds: 80)); // ✅ allow cleanup

    debugPrint("⛔ MIC FULLY STOPPED");
  }


  // ================= DISPOSE =================

  @override
  void dispose() {
    _micLocked = true;

    _startDelayTimer?.cancel();
    _autoStopTimer?.cancel();

    if (_isListening) {
      _speech.stop();
    }

    super.dispose();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    _documents = (widget.patientData['documents'] ?? []) as List<dynamic>;

    return WillPopScope(
      onWillPop: () async {
        await _goBackToSurgeonDashboard();
        return false; // ⛔ prevent app exit
      },
      child: Scaffold(

        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToSurgeonDashboard,
          ),
          title: Text("Patient History - ${widget.patientData['name']}"),
          backgroundColor: Colors.tealAccent.withOpacity(0.3),
        ),

        backgroundColor: Colors.grey[600],
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              _buildInfoCard("Patient ID", widget.patientData['patientId'] ?? 'N/A'),
              _buildInfoCard("Name", widget.patientData['name'] ?? 'N/A'),
              _buildInfoCard("Age", "${widget.patientData['age'] ?? 'N/A'}"),
              _buildInfoCard("Gender", widget.patientData['gender'] ?? 'N/A'),
              _buildInfoCard("Phone", widget.patientData['phone'] ?? 'N/A'),
              _buildInfoCard("Email", widget.patientData['email'] ?? 'N/A'),
              _buildInfoCard(
                  "Assigned Doctor", widget.patientData['assignedDoctor'] ?? 'N/A'),
              const SizedBox(height: 20),
              const Text(
                "📁 Uploaded Documents",
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (_documents.isEmpty)
                const Text(
                  "No documents uploaded.",
                  style: TextStyle(color: Colors.white70),
                )
              else
                ..._documents.map(
                      (doc) => Card(
                    color: Colors.white.withOpacity(0.05),
                    child: ListTile(
                      title: Text(
                        doc['fileName'] ?? 'Unknown',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new,
                            color: Colors.tealAccent),
                        onPressed: () {
                          if (_isNavigating) return;
                          _micLocked = true;
                          _stopMic();
                          _openDocument(
                            context,
                            doc['fileUrl'],
                            fileType: doc['fileType'],
                          );
                        },
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

  Widget _buildInfoCard(String label, String value) {
    return Card(
      color: Colors.white.withOpacity(0.08),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(label,
            style: const TextStyle(color: Colors.tealAccent)),
        subtitle:
        Text(value, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
