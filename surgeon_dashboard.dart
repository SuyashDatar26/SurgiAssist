import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_fonts/google_fonts.dart';
import 'package:surgiassist_ibip_lnct/screens/login_page.dart';
import 'package:surgiassist_ibip_lnct/screens/surgeon/procedure_summary.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../secrets.dart';
import '../admin/patient_history.dart';
import '../iamgeview_page.dart';
import '../pdfview_page.dart';
import 'patient_detail_page.dart';

class SurgeonDashboard extends StatefulWidget {
  const SurgeonDashboard({super.key});

  @override
  State<SurgeonDashboard> createState() => _SurgeonDashboardState();
}

class _SurgeonDashboardState extends State<SurgeonDashboard>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  Timer? _silenceTimer;


  String _voiceText = '';
  List<DocumentSnapshot> _searchResults = [];
  late TabController _tabController;
  late GenerativeModel _geminiModel;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

  }


  Future<String?> _getClosestMedicalTerm(String query) async {
    try {
      final model = GenerativeModel(
        model: "gemini-2.5-flash",
        apiKey: GEMINI_API_KEY, // Your Gemini API Key
      );

      final prompt = """
You are a medical terminology assistant.
The user said: "$query".

Your job:
- Correct spelling if needed.
- Interpret slang.
- Identify the closest real medical procedure or surgery.
- Reply ONLY with the correct medical term.
- Do NOT add extra text.

If no real medical procedure matches, reply with only: "UNKNOWN".
""";

      final response = await model.generateContent([Content.text(prompt)]);
      final answer = response.text?.trim() ?? "";

      if (answer.toUpperCase() == "UNKNOWN") {
        return null;
      }

      return answer; // corrected medical term
    } catch (e) {
      debugPrint("Medical term correction error: $e");
      return null;
    }
  }


  Future<Map<String, dynamic>> interpretVoiceCommandOffline(String command) async {
    final lower = command.toLowerCase();

    // LOGOUT
    if (lower.contains("logout") || lower.contains("sign out")) {
      return {"intent": "logout"};
    }

    // PROFILE
    if (lower.contains("profile")) {
      return {"intent": "view_profile"};
    }

    // SHOW ALL PATIENTS
    if (lower.contains("show all patients")) {
      return {"intent": "show_all_patients"};
    }

    // SEARCH PATIENT / OPEN PATIENT USING NAME OR ID
    if (lower.contains("find") || lower.contains("search") || lower.contains("open patient")) {
      final match = RegExp(r"(find|search|open patient)\s+(.+)").firstMatch(lower);
      return {
        "intent": "find_patient",
        "parameter": match?.group(2)?.trim()
      };
    }

    // OPEN ALL DOCUMENTS
    if (lower.contains("open documents") || lower.contains("show documents")) {
      return {"intent": "open_documents"};
    }

    // OPEN SINGLE DOCUMENT
    if (lower.contains("open document") || lower.contains("show document")
        || lower.contains("open file")) {
      final match = RegExp(r"(open|show)\s+(document|file)\s+(.+)").firstMatch(lower);
      return {
        "intent": "open_document",
        "parameter": match?.group(3)?.trim()
      };
    }

    // 🔥 NEW: MEDICAL WORKFLOW SEARCH
    if (lower.contains("search procedure") ||
        lower.contains("search workflow") ||
        lower.contains("search surgery") ||
        lower.contains("lookup") ||
        lower.contains("explain")) {

      final match = RegExp(
          r"(search procedure|search workflow|search surgery|lookup|explain)\s+(.+)"
      ).firstMatch(lower);

      return {
        "intent": "search_medical",
        "parameter": match?.group(2)?.trim(),
      };
    }

    // GO BACK
    if (lower.contains("back") || lower.contains("go back")) {
      return {"intent": "go_back"};
    }

    return {"intent": "unknown"};
  }


// 🎤 Start listening instantly and auto-search
  Future<void> _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) async {
        if (status == 'done') {

          // 🔥 Mic must stop BEFORE executing command
          stopMic();

          if (_voiceText.trim().isNotEmpty) {
            final intentData =
            await interpretVoiceCommandOffline(_voiceText.trim());
            await _handleVoiceIntent(intentData);
          }

          // ❌ Disable auto-restart after command execution
          // (do not call _startListening again)
        }
      },
      onError: (error) {
        stopMic();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Speech error: ${error.errorMsg}")),
        );
      },
    );

    if (available) {
      setState(() {
        _isListening = true;
        _voiceText = '';
      });

      _speech.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) async {

          _voiceText = result.recognizedWords;

          if (result.finalResult && _voiceText.trim().isNotEmpty) {

            // 🔥 Stop mic immediately before handling command
            stopMic();

            final intentData =
            await interpretVoiceCommandOffline(_voiceText.trim());

            await _handleVoiceIntent(intentData);

            // ❌ NO RESTART HERE!
          }
        },
      );
    }
  }

  Future<void> _handleVoiceIntent(Map<String, dynamic> intentData) async {

    // 🔥 Immediately stop mic before executing any command
    stopMic();
    final intent = intentData['intent'];
    final param = intentData['parameter'];



    switch (intent) {
      case "find_patient":
        await _searchPatients(param ?? "");
        break;

      case "open_documents":
        if (_searchResults.isNotEmpty) {
          final patient = _searchResults.first;
          final data = patient.data() as Map<String, dynamic>;
          _showDocumentsDialog(data);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No patient selected.")),
          );
        }
        break;

      case "open_document":
        if (_searchResults.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please find a patient first.")),
          );
          return;
        }

        final patient = _searchResults.first;
        final data = patient.data() as Map<String, dynamic>;
        final documents = List<Map<String, dynamic>>.from(data['documents'] ?? []);

        if (param == null || param.isEmpty) {
          _showDocumentsDialog(data);
          return;
        }

        final matchedDoc = documents.firstWhere(
              (doc) =>
          (doc['fileName']?.toString().toLowerCase().contains(param.toLowerCase()) ?? false),
          orElse: () => {},
        );

        if (matchedDoc.isNotEmpty) {
          _openDocument(context, matchedDoc['fileUrl'], fileType: matchedDoc['fileType']);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No document found matching \"$param\"")),
          );
        }
        break;

      case "show_all_patients":
        final snapshot = await FirebaseFirestore.instance.collection('patients').get();
        setState(() => _searchResults = snapshot.docs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Showing all patients")),
        );
        break;

      case "view_profile":
        _tabController.animateTo(2);
        break;

      case "go_back":
        Navigator.pop(context);
        break;

      case "logout":
        await _logout();
        break;
      case "search_medical":

        if (param == null || param.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please say a procedure name.")),
          );
          return;
        }

        // 🔥 Step 1: Ask Gemini to correct the term & return the closest medical match
        final correctedTerm = await _getClosestMedicalTerm(param);

        if (correctedTerm == null || correctedTerm.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't identify the medical procedure: $param")),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fetching details for: $correctedTerm")),
        );

        // 🔥 Step 2: Navigate with the corrected medical term
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcedureSummaryPage(procedureName: correctedTerm),
          ),
        );
        break;


      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Command not recognized")),
        );
        break;
    }
  }


  void _openDocument(BuildContext context, String? url, {String? fileType}) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No URL available for this file.")),
      );
      return;
    }

    final lowerUrl = url.toLowerCase();
    final isPdf = (fileType?.toLowerCase() == 'pdf') || lowerUrl.contains('.pdf');

    if (isPdf) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PDFViewerPage(pdfUrl: url)),
      );
    }
  }

  Widget _buildGradientBackground({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  void _showDocumentsDialog(Map<String, dynamic> data) {
    if (data['documents'] == null || data['documents'].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No documents available.")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        title: Text(
          "Patient Documents",
          style: GoogleFonts.poppins(
            color: Colors.tealAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          height: 200,
          width: 300,
          child: ListView.builder(
            itemCount: data['documents'].length,
            itemBuilder: (context, index) => ListTile(
              title: Text(
                "Document ${index + 1}",
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                data['documents'][index],
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }


// 🛑 Stop listening manually (optional)
  void _stopListening() {
    _speech.stop();
    _silenceTimer?.cancel();
    setState(() => _isListening = false);
  }


  void stopMic() {
    try {
      _speech.stop();
      _speech.cancel();  // extra safety
    } catch (_) {}

    _silenceTimer?.cancel();

    _isListening = false;
    setState(() {});
  }

// 🔍 Search for patients by voice text (case-insensitive fuzzy match)
  Future<void> _searchPatients(String queryText) async {
    if (queryText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please say a patient ID or name")),
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;

    String query = queryText.trim().toLowerCase();

    // -------------------------------------------
    // 1️⃣ NORMALIZE "P 9" / "p nine" / "p009"
    // -------------------------------------------
    query = query.replaceAll("patient", "").trim();

    // Convert number words to digits
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
      "nine": "9"
    };

    for (var e in numMap.entries) {
      query = query.replaceAll(e.key, e.value);
    }

    // Remove extra spaces
    query = query.replaceAll(RegExp(r"\s+"), " ").trim();

    // If the user said “p 9” or “p 09” or “p09”
    if (query.startsWith("p")) {
      String digits = query.replaceAll(RegExp(r"[^0-9]"), "");

      if (digits.isNotEmpty) {
        // Format to P ### (3 digits)
        final padded = digits.padLeft(3, '0');
        query = "P $padded";
      }
    }

    // -------------------------------------------
    // 2️⃣ SEARCH BY NORMALIZED PATIENT ID
    // -------------------------------------------
    final idQuery = await firestore
        .collection('patients')
        .where('patientId', isEqualTo: query.toUpperCase())
        .get();

    List<DocumentSnapshot> patients = idQuery.docs;

    // -------------------------------------------
    // 3️⃣ FALLBACK: NAME SEARCH (searchName array)
    // -------------------------------------------
    if (patients.isEmpty) {
      final nameQuery = await firestore
          .collection('patients')
          .where('searchName', arrayContains: query.toLowerCase())
          .get();
      patients = nameQuery.docs;
    }

    // -------------------------------------------
    // 4️⃣ FALLBACK: Standard name range match
    // -------------------------------------------
    if (patients.isEmpty) {
      final fallbackQuery = await firestore
          .collection('patients')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      patients = fallbackQuery.docs;
    }

    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No patient found for \"$queryText\"")),
      );
      return;
    }

    // OPEN PATIENT PAGE
    final foundPatient = patients.first;
    final patientData = foundPatient.data() as Map<String, dynamic>;
    stopMic();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PatientHistoryPage(
          patientId: foundPatient.id,
          patientData: patientData,
        ),
      ),
    );
  }


  // 🚪 Logout
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false,
    );
  }

  // 🧾 Patient card UI
  Widget _buildPatientCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final patientId = doc.id;  // ✔ Correct Firestore document ID

    return Card(
      color: const Color(0xFF1B2A33),
      shadowColor: Colors.black54,
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.person, color: Colors.tealAccent, size: 30),

        title: Text(
          data['name'] ?? 'Unknown',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),

        subtitle: Text(
          "Patient ID: $patientId\n"
              "Age: ${data['age']} | Gender: ${data['gender']}\n"
              "Doctor: ${data['assignedDoctor']}",
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 13,
            height: 1.4,
          ),
        ),

        onTap: () {
          // 👇 Navigate to Patient History Page with correct ID + data
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PatientHistoryPage(
                patientId: patientId,
                patientData: data,
              ),
            ),
          );
        },

        trailing: IconButton(
          icon: const Icon(Icons.folder_open_rounded, color: Colors.tealAccent),
          onPressed: () {
            if (data['documents'] == null || data['documents'].isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("No documents available.")),
              );
            } else {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF0F2027),
                  title: Text(
                    "Patient Documents",
                    style: GoogleFonts.poppins(
                        color: Colors.tealAccent, fontWeight: FontWeight.bold),
                  ),
                  content: SizedBox(
                    height: 200,
                    width: 300,
                    child: ListView.builder(
                      itemCount: data['documents'].length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(
                          "Document ${index + 1}",
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          data['documents'][index]['fileName'] ?? "",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  // 🎨 Gradient background wrapper


  // ⚙️ SETTINGS / PROFILE TAB
// ⚙️ SETTINGS TAB (Fully Functional)
  Widget _buildSettings() {
    final user = FirebaseAuth.instance.currentUser;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user!.uid);

    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmPasswordController =
    TextEditingController();

    return _buildGradientBackground(
      child: StreamBuilder<DocumentSnapshot>(
        stream: userDoc.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          nameController.text = data['name'] ?? user.displayName ?? 'Admin';
          final email = data['email'] ?? user.email ?? 'N/A';
          final photoUrl = data['photoUrl'] ??
              'https://cdn-icons-png.flaticon.com/512/3135/3135715.png';

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),

                // 👤 Profile Picture
                CircleAvatar(
                  radius: 55,
                  backgroundImage: NetworkImage(photoUrl),
                  backgroundColor: Colors.tealAccent.withOpacity(0.3),
                ),
                const SizedBox(height: 20),

                // 🧑 Name
                Text(
                  nameController.text,
                  style: GoogleFonts.poppins(
                    color: Colors.tealAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // 📧 Email
                Text(
                  email,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 30),

                // ✏️ Edit Profile Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit, color: Colors.black87),
                  label: const Text("Edit Profile"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _showEditProfileDialog(
                      context, userDoc, nameController, photoUrl),
                ),
                const SizedBox(height: 20),

                // 🔑 Change Password
                ElevatedButton.icon(
                  icon: const Icon(Icons.lock_reset_rounded,
                      color: Colors.black87),
                  label: const Text("Change Password"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _showChangePasswordDialog(
                      context, passwordController, confirmPasswordController),
                ),
                const SizedBox(height: 30),

                // 🚪 Logout Button
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.9),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 50),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 10,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 🧾 Edit Profile Dialog
  void _showEditProfileDialog(BuildContext context, DocumentReference userDoc,
      TextEditingController nameController, String currentPhotoUrl)
  {
    final TextEditingController photoController =
    TextEditingController(text: currentPhotoUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Edit Profile",
            style: GoogleFonts.poppins(
                color: Colors.tealAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Full Name",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: photoController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Profile Photo URL",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () async {
              await userDoc.update({
                'name': nameController.text.trim(),
                'photoUrl': photoController.text.trim(),
              });

              await FirebaseAuth.instance.currentUser!
                  .updateDisplayName(nameController.text.trim());
              await FirebaseAuth.instance.currentUser!
                  .updatePhotoURL(photoController.text.trim());

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Profile updated successfully!"),
                  backgroundColor: Colors.teal,
                ),
              );
            },
            child: const Text("Save", style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  /// 🔑 Change Password Dialog
  void _showChangePasswordDialog(BuildContext context,
      TextEditingController passwordController,
      TextEditingController confirmPasswordController)
  {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Change Password",
            style: GoogleFonts.poppins(
                color: Colors.tealAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "New Password",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Confirm Password",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () async {
              if (passwordController.text.trim() !=
                  confirmPasswordController.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Passwords do not match!"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              try {
                await FirebaseAuth.instance.currentUser!
                    .updatePassword(passwordController.text.trim());
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Password updated successfully!"),
                    backgroundColor: Colors.teal,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error: $e"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child:
            const Text("Update", style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SurgiAssist - Surgeon',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.mic), text: 'Voice Assistant'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Patients'),
            Tab(icon: Icon(Icons.settings), text: 'Profile'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 🎤 Voice Assistant Tab
          _buildGradientBackground(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                children: [
                  Text(
                    'Voice Assistant',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton.icon(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.black,
                      ),
                      label: Text(
                        _isListening ? 'Listening...' : 'Start Command',
                        style: const TextStyle(color: Colors.black),
                      ),
                      onPressed: _isListening ? _stopListening : _startListening,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent.withOpacity(0.9),
                        minimumSize: const Size(230, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Text(
                    "Recognized Command:",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _voiceText.isEmpty ? 'Say a patient’s name...' : _voiceText,
                    style: GoogleFonts.poppins(
                      color: Colors.tealAccent,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _searchPatients(_voiceText.trim());
                    },
                    icon: const Icon(Icons.search, color: Colors.black),
                    label: const Text(
                      'Fetch Patient Data',
                      style: TextStyle(color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.withOpacity(0.9),
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 8,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (_searchResults.isEmpty)
                    Center(
                      child: Text(
                        "No patients found.",
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    )
                  else
                    ..._searchResults.map(_buildPatientCard),
                ],
              ),
            ),
          ),

          // 🧾 Patients Tab
          _buildGradientBackground(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('patients')
                  .where('assignedDoctor',
                  isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.tealAccent),
                  );
                }

                final patients = snapshot.data!.docs;
                if (patients.isEmpty) {
                  return Center(
                    child: Text(
                      "No patients assigned yet.",
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: patients.length,
                  itemBuilder: (context, index) =>
                      _buildPatientCard(patients[index]),
                );
              },
            ),
          ),

          // ⚙️ Profile / Settings Tab
          _buildSettings(),
        ],
      ),
    );
  }
}
