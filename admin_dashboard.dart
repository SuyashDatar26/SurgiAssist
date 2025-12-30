import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:surgiassist_ibip_lnct/screens/admin/patient_history.dart';
import '../login_page.dart';
import 'package:firebase_ml_model_downloader/firebase_ml_model_downloader.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class AdminDashboard extends StatefulWidget {
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _doctorController = TextEditingController();

  late Interpreter _interpreter;
  bool _modelLoaded = false;
  final int inputSize = 640; // change to your model's expected size

  String? remoteModelPath; // local downloaded model path
  final String inferenceUrl = "https://YOUR_CLOUD_FUNCTION_URL/predict";



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this); // 5 Tabs now
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/model_to_convert_float16.tflite',
        options: InterpreterOptions()..threads = 4,
      );

      setState(() => _modelLoaded = true);
      print("MODEL LOADED SUCCESSFULLY");
    } catch (e) {
      print("MODEL LOAD ERROR: $e");
    }
  }

  Float32List preprocessImage(File file, int inputSize) {
    final bytes = file.readAsBytesSync();
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception("Image decode failed");

    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    final Float32List input = Float32List(1 * inputSize * inputSize * 3);
    int index = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        input[index++] = p.r / 255.0;
        input[index++] = p.g / 255.0;
        input[index++] = p.b / 255.0;
      }
    }

    return input;
  }

  List<List<double>> runModel(File imageFile) {
    final input = preprocessImage(imageFile, inputSize);

    final output = List.generate(
      1,
          (_) => List.generate(11, (_) => List.filled(8400, 0.0)),
    );

    _interpreter.run(
      input.reshape([1, inputSize, inputSize, 3]),
      output,
    );

    final List<List<double>> rawDetections = [];

    for (int i = 0; i < 8400; i++) {
      final cx = sigmoid(output[0][0][i]);
      final cy = sigmoid(output[0][1][i]);
      final w  = sigmoid(output[0][2][i]);
      final h  = sigmoid(output[0][3][i]);

      double maxClassProb = 0.0;
      for (int c = 4; c < 11; c++) {
        final prob = sigmoid(output[0][c][i]);
        if (prob > maxClassProb) maxClassProb = prob;
      }

      // 🔥 Stronger confidence threshold
      if (maxClassProb < 0.45) continue;

      rawDetections.add([cx, cy, w, h, maxClassProb]);
    }

    // 🔥 APPLY NMS
    final finalDetections = nonMaxSuppression(
      rawDetections,
      iouThreshold: 0.5,
      maxBoxes: 10,
    );

    print("Final detections after NMS: ${finalDetections.length}");
    return finalDetections;
  }

  Future<File> drawBoxes(File file, List<List<double>> detections) async {
    final image = img.decodeImage(await file.readAsBytes());
    if (image == null) throw Exception("Image decode failed");

    final int imgW = image.width;
    final int imgH = image.height;

    final double scaleX = imgW / inputSize;
    final double scaleY = imgH / inputSize;

    for (var det in detections) {
      final cx = det[0] * inputSize;
      final cy = det[1] * inputSize;
      final w  = det[2] * inputSize;
      final h  = det[3] * inputSize;
      final conf = det[4];

      final double x1 = (cx - w / 2) * scaleX;
      final double y1 = (cy - h / 2) * scaleY;
      final double x2 = (cx + w / 2) * scaleX;
      final double y2 = (cy + h / 2) * scaleY;

      img.drawRect(
        image,
        x1: x1.clamp(0, imgW - 1).toInt(),
        y1: y1.clamp(0, imgH - 1).toInt(),
        x2: x2.clamp(0, imgW - 1).toInt(),
        y2: y2.clamp(0, imgH - 1).toInt(),
        color: img.ColorRgb8(255, 0, 0),
        thickness: 1, // 🔥 medical-grade thin
      );
    }

    final boxedPath = file.path.replaceFirst(
      RegExp(r'\.(jpg|jpeg|png)$'),
      '_boxed.jpg',
    );

    final boxedFile = File(boxedPath);
    await boxedFile.writeAsBytes(img.encodeJpg(image));
    return boxedFile;
  }


  double sigmoid(double x) {
    return 1 / (1 + math.exp(-x));
  }
  double iou(List<double> a, List<double> b) {
    final ax1 = a[0] - a[2] / 2;
    final ay1 = a[1] - a[3] / 2;
    final ax2 = a[0] + a[2] / 2;
    final ay2 = a[1] + a[3] / 2;

    final bx1 = b[0] - b[2] / 2;
    final by1 = b[1] - b[3] / 2;
    final bx2 = b[0] + b[2] / 2;
    final by2 = b[1] + b[3] / 2;

    final interX1 = math.max(ax1, bx1);
    final interY1 = math.max(ay1, by1);
    final interX2 = math.min(ax2, bx2);
    final interY2 = math.min(ay2, by2);

    final interArea =
        math.max(0, interX2 - interX1) * math.max(0, interY2 - interY1);

    final areaA = (ax2 - ax1) * (ay2 - ay1);
    final areaB = (bx2 - bx1) * (by2 - by1);

    return interArea / (areaA + areaB - interArea + 1e-6);
  }

  List<List<double>> nonMaxSuppression(
      List<List<double>> boxes, {
        double iouThreshold = 0.45,
        int maxBoxes = 15,
      })
  {
    boxes.sort((a, b) => b[4].compareTo(a[4])); // sort by confidence

    final List<List<double>> selected = [];

    for (final box in boxes) {
      bool keep = true;
      for (final sel in selected) {
        if (iou(box, sel) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) selected.add(box);
      if (selected.length >= maxBoxes) break;
    }

    return selected;
  }



  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false,
    );
  }

  Future<void> _addPatient() async {
    final name = _nameController.text.trim();
    final age = _ageController.text.trim();
    final doctor = _doctorController.text.trim();

    if (name.isEmpty || age.isEmpty || doctor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('patients').add({
      'name': name,
      'age': age,
      'assignedDoctor': doctor,
      'createdAt': Timestamp.now(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patient added successfully')),
    );

    _nameController.clear();
    _ageController.clear();
    _doctorController.clear();
  }

  Future<void> _showAddDoctorDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController specializationController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add New Doctor"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Full Name"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: "Email Address"),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: specializationController,
                  decoration: const InputDecoration(labelText: "Specialization"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("Add"),
              onPressed: () async {
                final name = nameController.text.trim();
                final email = emailController.text.trim();
                final specialization = specializationController.text.trim();

                if (name.isEmpty || email.isEmpty || specialization.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                Navigator.pop(context);
                await _createDoctorAccount(name, email, specialization);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _createDoctorAccount(String name, String email, String specialization) async {
    try {
      // Initialize a secondary Firebase app
      final FirebaseApp tempApp = await Firebase.initializeApp(
        name: 'tempApp',
        options: Firebase.app().options,
      );

      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      // Generate a random password for the doctor
      final password = "doc@${DateTime.now().millisecondsSinceEpoch}";

      // Create doctor account
      UserCredential newDoctor = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Add doctor details to Firestore
      await FirebaseFirestore.instance.collection('doctors').doc(newDoctor.user!.uid).set({
        'name': name,
        'email': email,
        'specialization': specialization,
        'createdAt': Timestamp.now(),
        'generatedPassword': password,
      });

      await tempApp.delete(); // clean up

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Doctor added successfully!\nGenerated Password: $password"),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error adding doctor: $e")),
      );
    }
  }


  Future<void> _deleteDoctor(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('doctors').doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Doctor deleted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting doctor: $e")),
      );
    }
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
          'SurgiAssist',
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
            Tab(icon: Icon(Icons.person_add), text: 'Add Patient'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Patients'),
            Tab(icon: Icon(Icons.local_hospital), text: 'Doctors'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Analytics'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddPatientTab(),
          _buildRegisteredPatientsTab(),
          _buildManageDoctors(),
          _buildAnalytics(),
          _buildSettings(),
        ],
      ),
    );
  }

  // 👩‍⚕️ ADD PATIENT TAB
// 📋 ADD PATIENT TAB (Enhanced + Firestore + File Upload)
// 📋 ADD PATIENT TAB (Supports PDF + Image Uploads via File Picker)
  Widget _buildAddPatientTab() {
    final TextEditingController _nameController = TextEditingController();
    final TextEditingController _ageController = TextEditingController();
    final TextEditingController _phoneController = TextEditingController();
    final TextEditingController _emailController = TextEditingController();




    String? selectedGender;
    String? selectedDoctor;
    List<PlatformFile> selectedFiles = [];
    List<Map<String, dynamic>> uploadedDocs = [];




    // 📤 Pick Documents (Show file names)
    Future<void> _pickDocuments() async {
      try {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        );

        if (result != null && result.files.isNotEmpty) {
          selectedFiles = result.files;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${selectedFiles.length} files selected")),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error selecting files: $e")),
        );
      }
    }

    // 🔢 Generate next patientId
    Future<String> _generatePatientId() async {
      final snapshot = await FirebaseFirestore.instance
          .collection('patients')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return "P 001";

      final lastPatient = snapshot.docs.first.data();
      final lastId = (lastPatient['patientId'] ?? "P 000").toString();
      final numericPart =
          int.tryParse(lastId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return "P ${(numericPart + 1).toString().padLeft(3, '0')}";
    }

    // ➕ Add Patient (uploads files + adds Firestore entry)
    Future<void> _addPatient() async {
      if (_nameController.text.isEmpty ||
          _ageController.text.isEmpty ||
          _phoneController.text.isEmpty ||
          _emailController.text.isEmpty ||
          selectedDoctor == null ||
          selectedGender == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill all required fields")),
        );
        return;
      }

      try {
        final patientId = await _generatePatientId();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Uploading files...")),
        );

        // Upload all selected files
        for (var file in selectedFiles) {
          final filePath = file.path;
          if (filePath == null) continue;

          final fileExtension = file.extension ?? '';
          final fileType = fileExtension.toLowerCase();
          final fileName =
              'patients/${patientId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          final ref = FirebaseStorage.instance.ref().child(fileName);

          File originalFile = File(filePath);
          File fileToUpload = originalFile;

          // Only run the YOLO model on images
          final bool isImage = ['jpg', 'jpeg', 'png'].contains(fileType);

          if (isImage && _modelLoaded) {
            try {
              final detections = runModel(originalFile);
              fileToUpload = await drawBoxes(originalFile, detections);
            } catch (e) {
              debugPrint("⚠️ Error running model on image ${file.name}: $e");
              // fallback: upload original image
              fileToUpload = originalFile;
            }
          }

          await ref.putFile(fileToUpload);
          final url = await ref.getDownloadURL();

          uploadedDocs.add({
            'fileName': file.name,
            'fileType': fileType,
            'fileUrl': url,
            'uploadedAt': DateTime.now().toIso8601String(),
          });
        }

        // Save patient data
        await FirebaseFirestore.instance.collection('patients').add({
          'patientId': patientId,
          'name': _nameController.text.trim(),
          'age': int.parse(_ageController.text.trim()),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'gender': selectedGender,
          'assignedDoctor': selectedDoctor,
          'documents': uploadedDocs,
          'createdAt': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Patient added successfully! ID: $patientId")),
        );

        // Reset fields
        _nameController.clear();
        _ageController.clear();
        _phoneController.clear();
        _emailController.clear();
        selectedGender = null;
        selectedDoctor = null;
        selectedFiles.clear();
        uploadedDocs.clear();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error adding patient: $e")),
        );
      }
    }

    // 🩺 UI Layout
    return _buildGradientBackground(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader("Add New Patient"),
          const SizedBox(height: 15),

          _buildTextField(_nameController, "Patient Name", Icons.person_outline),
          const SizedBox(height: 12),

          _buildTextField(
            _emailController,
            "Email",
            Icons.email_outlined,
            inputType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          _buildTextField(
            _phoneController,
            "Phone Number",
            Icons.phone_outlined,
            inputType: TextInputType.number,
          ),
          const SizedBox(height: 12),

          _buildTextField(
            _ageController,
            "Age",
            Icons.calendar_today_outlined,
            inputType: TextInputType.number,
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black),
            value: selectedGender,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.wc_outlined, color: Colors.tealAccent),
              labelText: "Gender",
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.tealAccent.withOpacity(0.4)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: "Male", child: Text("Male")),
              DropdownMenuItem(value: "Female", child: Text("Female")),
              DropdownMenuItem(value: "Other", child: Text("Other")),
            ],
            onChanged: (value) => selectedGender = value,
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'surgeon')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final doctors = snapshot.data!.docs;

              return DropdownButtonFormField<String>(
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  prefixIcon:
                  const Icon(Icons.local_hospital, color: Colors.tealAccent),
                  labelText: "Assign Doctor",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                    BorderSide(color: Colors.tealAccent.withOpacity(0.4)),
                  ),
                ),
                items: doctors.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text("${data['name']} (${data['email']})"),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedDoctor = value;
                },
              );
            },
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _pickDocuments,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text("Select Documents (PDF / Image)"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.tealAccent.withOpacity(0.9),
              foregroundColor: Colors.black,
              textStyle:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),

          // 📋 Show selected file names
          if (selectedFiles.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: selectedFiles
                  .map((file) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  "📄 ${file.name}",
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                ),
              ))
                  .toList(),
            ),

          const SizedBox(height: 25),

          ElevatedButton.icon(
            onPressed: _addPatient,
            icon: const Icon(Icons.add),
            label: const Text("Add Patient"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 55),
              backgroundColor: Colors.tealAccent.withOpacity(0.9),
              foregroundColor: Colors.black,
              textStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // 🧾 REGISTERED PATIENTS TAB
  Widget _buildRegisteredPatientsTab() {
    return _buildGradientBackground(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('patients')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final patients = snapshot.data!.docs;
          if (patients.isEmpty) {
            return const Center(
              child: Text(
                'No patients registered yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final doc = patients[index];
              final data = doc.data() as Map<String, dynamic>;

              return InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PatientHistoryPage(
                        patientId: doc.id,
                        patientData: data,
                      ),
                    ),
                  );
                },
                child: Card(
                  color: Colors.white.withOpacity(0.1),
                  elevation: 6,
                  shadowColor: Colors.tealAccent.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.person, color: Colors.tealAccent),
                    title: Text(
                      data['name'] ?? 'Unknown',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Doctor: ${data['assignedDoctor'] ?? 'N/A'} | Age: ${data['age'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever,
                          color: Colors.redAccent),
                      onPressed: () async {
                        await doc.reference.delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Patient deleted')),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 🧑‍⚕️ DOCTOR MANAGEMENT TAB
  Widget _buildManageDoctors() {
    return _buildGradientBackground(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Manage Doctors",
                  style: GoogleFonts.poppins(
                    color: Colors.tealAccent,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
                  label: const Text("Add Doctor"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withOpacity(0.9),
                    foregroundColor: Colors.black,
                    elevation: 10,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    shadowColor: Colors.tealAccent.withOpacity(0.5),
                  ),
                  onPressed: _showAddDoctorDialog,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Subheader
            Text(
              "List of Registered Doctors",
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Stream List of Doctors
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'surgeon')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.tealAccent,
                      ),
                    );
                  }

                  final doctors = snapshot.data!.docs;

                  if (doctors.isEmpty) {
                    return Center(
                      child: Text(
                        "No doctors registered yet.",
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: doctors.length,
                    itemBuilder: (context, index) {
                      final data = doctors[index].data() as Map<String, dynamic>;
                      final docId = doctors[index].id;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.tealAccent.withOpacity(0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.tealAccent.withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          leading: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00BFA6), Color(0xFF1DE9B6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.tealAccent.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(
                              Icons.local_hospital_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            data['name'] ?? 'Unnamed Doctor',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Specialization: ${data['specialization'] ?? 'N/A'}",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  "Email: ${data['email'] ?? 'N/A'}",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                if (data['phone'] != null)
                                  Text(
                                    "Phone: ${data['phone']}",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever_rounded,
                                color: Colors.redAccent, size: 30),
                            onPressed: () => _deleteDoctor(docId),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

// 📊 ANALYTICS TAB (Fully Functional)
  Widget _buildAnalytics() {
    final doctorsStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'surgeon')
        .snapshots();

    final patientsStream =
    FirebaseFirestore.instance.collection('patients').snapshots();

    return _buildGradientBackground(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Analytics Dashboard",
              style: GoogleFonts.poppins(
                color: Colors.tealAccent,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Real-time overview of system activity",
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 30),

            // 👥 Row of Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Total Doctors
                StreamBuilder<QuerySnapshot>(
                  stream: doctorsStream,
                  builder: (context, snapshot) {
                    int totalDoctors = snapshot.hasData
                        ? snapshot.data!.docs.length
                        : 0;
                    return _buildAnalyticsCard(
                      title: "Doctors Working",
                      value: totalDoctors.toString(),
                      icon: Icons.local_hospital_rounded,
                      color1: const Color(0xFF00BFA6),
                      color2: const Color(0xFF1DE9B6),
                    );
                  },
                ),

                // Total Patients
                StreamBuilder<QuerySnapshot>(
                  stream: patientsStream,
                  builder: (context, snapshot) {
                    int totalPatients = snapshot.hasData
                        ? snapshot.data!.docs.length
                        : 0;
                    return _buildAnalyticsCard(
                      title: "Patients Enrolled",
                      value: totalPatients.toString(),
                      icon: Icons.people_alt_rounded,
                      color1: const Color(0xFF26C6DA),
                      color2: const Color(0xFF00ACC1),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 40),

            // 📈 Placeholder for future analytics (like ML insights)
            Center(
              child: Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.tealAccent.withOpacity(0.3), width: 1.2),
                ),
                child: Center(
                  child: Text(
                    "AI Insights & Trends Coming Soon",
                    style: GoogleFonts.poppins(
                      color: Colors.white54,
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 📦 Reusable Analytics Card Widget
  Widget _buildAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color1,
    required Color color2,
  }) {
    return Container(
      width: 160,
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1, color2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 38),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

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


  // 🌈 COMMON BACKGROUND WRAPPER
  Widget _buildGradientBackground({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF203A43), Color(0xFF2C5364)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  // 📍 COMMON SECTION HEADER
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // 🧱 COMMON TEXT FIELD BUILDER
  Widget _buildTextField(TextEditingController controller, String label, IconData icon,
      {TextInputType inputType = TextInputType.text})
  {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.tealAccent),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.tealAccent),
        ),
      ),
    );
  }

  // 🎨 PLACEHOLDER FOR NON-IMPLEMENTED TABS
  Widget _buildPlaceholderView({
    required String title,
    required String description,
    required IconData icon,
  })
  {
    return _buildGradientBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.tealAccent, size: 70),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 15, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
