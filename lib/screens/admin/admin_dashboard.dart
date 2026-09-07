import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ml_model_downloader/firebase_ml_model_downloader.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:surgiassist_ibip_lnct/screens/admin/patient_history.dart';
import '../login_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  // ===========================================================================
  // THEME
  // ===========================================================================

  static const Color _background = Color(0xFF06131F);
  static const Color _backgroundMid = Color(0xFF0A1E2D);
  static const Color _surface = Color(0xFF0F2738);
  static const Color _surfaceLight = Color(0xFF14354A);

  static const Color _teal = Color(0xFF0E7490);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _cyanLight = Color(0xFF67E8F9);

  static const Color _white = Color(0xFFF8FAFC);
  static const Color _secondaryText = Color(0xFF9DB2C1);
  static const Color _mutedText = Color(0xFF6F8796);

  static const Color _success = Color(0xFF34D399);
  static const Color _warning = Color(0xFFFBBF24);
  static const Color _danger = Color(0xFFFB7185);
  static const Color _purple = Color(0xFFA78BFA);

  // ===========================================================================
  // TAB
  // ===========================================================================

  late TabController _tabController;

  // ===========================================================================
  // PATIENT FORM CONTROLLERS
  // ===========================================================================

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  String? _selectedGender;
  String? _selectedDoctor;

  List<PlatformFile> _selectedFiles = [];
  bool _isAddingPatient = false;
  double _uploadProgress = 0;

  // ===========================================================================
  // MODEL
  // ===========================================================================

  late Interpreter _interpreter;
  bool _modelLoaded = false;

  final int inputSize = 640;

  String? remoteModelPath;

  final String inferenceUrl =
      "https://YOUR_CLOUD_FUNCTION_URL/predict";

  // ===========================================================================
  // PATIENT SEARCH
  // ===========================================================================

  final TextEditingController _patientSearchController =
  TextEditingController();

  String _patientSearchQuery = '';

  // ===========================================================================
  // ANIMATIONS
  // ===========================================================================

  late AnimationController _pageController;
  late AnimationController _backgroundController;
  late AnimationController _pulseController;

  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;
  late Animation<double> _pulseAnimation;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 5,
      vsync: this,
    );

    _setupAnimations();
    _loadModel();

    _patientSearchController.addListener(() {
      if (!mounted) return;

      setState(() {
        _patientSearchQuery =
            _patientSearchController.text.trim().toLowerCase();
      });
    });
  }

  void _setupAnimations() {
    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pageFade = CurvedAnimation(
      parent: _pageController,
      curve: Curves.easeOutCubic,
    );

    _pageSlide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageController,
        curve: Curves.easeOutCubic,
      ),
    );

    _pulseAnimation = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _pageController.forward();
    _backgroundController.repeat();
    _pulseController.repeat(reverse: true);
  }

  // ===========================================================================
  // MODEL
  // ===========================================================================

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/model_to_convert_float16.tflite',
        options: InterpreterOptions()..threads = 4,
      );

      if (!mounted) return;

      setState(() {
        _modelLoaded = true;
      });

      debugPrint("MODEL LOADED SUCCESSFULLY");
    } catch (e) {
      debugPrint("MODEL LOAD ERROR: $e");
    }
  }

  Float32List preprocessImage(
      File file,
      int inputSize,
      ) {
    final bytes = file.readAsBytesSync();

    final img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception("Image decode failed");
    }

    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    final Float32List input = Float32List(
      1 * inputSize * inputSize * 3,
    );

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

  List<List<double>> runModel(
      File imageFile,
      ) {
    final input = preprocessImage(
      imageFile,
      inputSize,
    );

    final output = List.generate(
      1,
          (_) => List.generate(
        11,
            (_) => List.filled(
          8400,
          0.0,
        ),
      ),
    );

    _interpreter.run(
      input.reshape(
        [
          1,
          inputSize,
          inputSize,
          3,
        ],
      ),
      output,
    );

    final List<List<double>> rawDetections = [];

    for (int i = 0; i < 8400; i++) {
      final cx = sigmoid(output[0][0][i]);
      final cy = sigmoid(output[0][1][i]);
      final w = sigmoid(output[0][2][i]);
      final h = sigmoid(output[0][3][i]);

      double maxClassProb = 0.0;

      for (int c = 4; c < 11; c++) {
        final prob = sigmoid(output[0][c][i]);

        if (prob > maxClassProb) {
          maxClassProb = prob;
        }
      }

      if (maxClassProb < 0.45) {
        continue;
      }

      rawDetections.add(
        [
          cx,
          cy,
          w,
          h,
          maxClassProb,
        ],
      );
    }

    final finalDetections = nonMaxSuppression(
      rawDetections,
      iouThreshold: 0.5,
      maxBoxes: 10,
    );

    debugPrint(
      "Final detections after NMS: ${finalDetections.length}",
    );

    return finalDetections;
  }

  Future<File> drawBoxes(
      File file,
      List<List<double>> detections,
      ) async {
    final image = img.decodeImage(
      await file.readAsBytes(),
    );

    if (image == null) {
      throw Exception("Image decode failed");
    }

    final int imgW = image.width;
    final int imgH = image.height;

    final double scaleX = imgW / inputSize;
    final double scaleY = imgH / inputSize;

    for (final det in detections) {
      final cx = det[0] * inputSize;
      final cy = det[1] * inputSize;
      final w = det[2] * inputSize;
      final h = det[3] * inputSize;

      final double x1 =
          (cx - w / 2) * scaleX;

      final double y1 =
          (cy - h / 2) * scaleY;

      final double x2 =
          (cx + w / 2) * scaleX;

      final double y2 =
          (cy + h / 2) * scaleY;

      img.drawRect(
        image,
        x1: x1.clamp(0, imgW - 1).toInt(),
        y1: y1.clamp(0, imgH - 1).toInt(),
        x2: x2.clamp(0, imgW - 1).toInt(),
        y2: y2.clamp(0, imgH - 1).toInt(),
        color: img.ColorRgb8(
          255,
          0,
          0,
        ),
        thickness: 1,
      );
    }

    final boxedPath = file.path.replaceFirst(
      RegExp(
        r'\.(jpg|jpeg|png)$',
      ),
      '_boxed.jpg',
    );

    final boxedFile = File(boxedPath);

    await boxedFile.writeAsBytes(
      img.encodeJpg(image),
    );

    return boxedFile;
  }

  double sigmoid(double x) {
    return 1 / (1 + math.exp(-x));
  }

  double iou(
      List<double> a,
      List<double> b,
      ) {
    final ax1 = a[0] - a[2] / 2;
    final ay1 = a[1] - a[3] / 2;
    final ax2 = a[0] + a[2] / 2;
    final ay2 = a[1] + a[3] / 2;

    final bx1 = b[0] - b[2] / 2;
    final by1 = b[1] - b[3] / 2;
    final bx2 = b[0] + b[2] / 2;
    final by2 = b[1] + b[3] / 2;

    final interX1 = math.max(
      ax1,
      bx1,
    );

    final interY1 = math.max(
      ay1,
      by1,
    );

    final interX2 = math.min(
      ax2,
      bx2,
    );

    final interY2 = math.min(
      ay2,
      by2,
    );

    final interArea =
        math.max(
          0,
          interX2 - interX1,
        ) *
            math.max(
              0,
              interY2 - interY1,
            );

    final areaA =
        (ax2 - ax1) *
            (ay2 - ay1);

    final areaB =
        (bx2 - bx1) *
            (by2 - by1);

    return interArea /
        (areaA + areaB - interArea + 1e-6);
  }

  List<List<double>> nonMaxSuppression(
      List<List<double>> boxes, {
        double iouThreshold = 0.45,
        int maxBoxes = 15,
      }) {
    boxes.sort(
          (a, b) => b[4].compareTo(a[4]),
    );

    final List<List<double>> selected = [];

    for (final box in boxes) {
      bool keep = true;

      for (final sel in selected) {
        if (iou(box, sel) > iouThreshold) {
          keep = false;
          break;
        }
      }

      if (keep) {
        selected.add(box);
      }

      if (selected.length >= maxBoxes) {
        break;
      }
    }

    return selected;
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
          (route) => false,
    );
  }

// ===========================================================================
// ADD PATIENT
// ===========================================================================
//
// STORAGE ARCHITECTURE
//
// Firebase Firestore
//   └── patients/{firestoreDocumentId}
//         ├── patientId
//         ├── name
//         ├── age
//         ├── phone
//         ├── email
//         ├── gender
//         ├── assignedDoctor
//         ├── documents[]
//         │     ├── fileName
//         │     ├── fileType
//         │     ├── fileUrl
//         │     ├── storagePath
//         │     └── uploadedAt
//         └── createdAt
//
// Supabase Storage
//   └── patient-documents/
//         └── patients/
//               └── P 001/
//                     ├── xray.jpg
//                     ├── xray_boxed.jpg
//                     └── report.pdf
//
// ===========================================================================

  static const String _supabasePatientBucket =
      'patient-documents';

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'png',
          'jpg',
          'jpeg',
        ],
      );

      if (result != null && result.files.isNotEmpty) {
        if (!mounted) return;

        setState(() {
          _selectedFiles = result.files;
        });

        _showSnack(
          "${_selectedFiles.length} file(s) selected.",
          success: true,
        );
      }
    } catch (e) {
      debugPrint(
        "DOCUMENT PICKER ERROR: $e",
      );

      if (!mounted) return;

      _showSnack(
        "Error selecting files: $e",
      );
    }
  }

// ===========================================================================
// GENERATE PATIENT ID
// ===========================================================================

  Future<String> _generatePatientId() async {
    final snapshot = await FirebaseFirestore
        .instance
        .collection('patients')
        .orderBy(
      'createdAt',
      descending: true,
    )
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return "P 001";
    }

    final lastPatient =
    snapshot.docs.first.data();

    final lastId =
    (lastPatient['patientId'] ??
        "P 000")
        .toString();

    final numericPart =
        int.tryParse(
          lastId.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          ),
        ) ??
            0;

    return "P ${(numericPart + 1).toString().padLeft(3, '0')}";
  }

// ===========================================================================
// SUPABASE FILE HELPERS
// ===========================================================================

  String _sanitizeStorageFileName(
      String fileName,
      ) {
    final sanitized = fileName
        .trim()
        .replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );

    if (sanitized.isEmpty) {
      return 'document';
    }

    return sanitized;
  }

  String _getMimeType(
      String extension,
      ) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';

      case 'png':
        return 'image/png';

      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';

      default:
        return 'application/octet-stream';
    }
  }

// ===========================================================================
// DELETE SUPABASE FILES
//
// Used as rollback protection if Firestore fails after files have already
// been uploaded.
// ===========================================================================

  Future<void> _deleteSupabaseFiles(
      List<String> storagePaths,
      ) async {
    if (storagePaths.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client
          .storage
          .from(_supabasePatientBucket)
          .remove(storagePaths);

      debugPrint(
        "Supabase rollback completed for "
            "${storagePaths.length} file(s).",
      );
    } catch (e) {
      debugPrint(
        "SUPABASE ROLLBACK ERROR: $e",
      );
    }
  }

// ===========================================================================
// ADD PATIENT
// ===========================================================================

  Future<void> _addPatient() async {
    if (_isAddingPatient) return;

    final name =
    _nameController.text.trim();

    final ageText =
    _ageController.text.trim();

    final phone =
    _phoneController.text.trim();

    final email =
    _emailController.text.trim();

    // -------------------------------------------------------------------------
    // VALIDATION
    // -------------------------------------------------------------------------

    if (name.isEmpty ||
        ageText.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        _selectedDoctor == null ||
        _selectedGender == null) {
      _showSnack(
        "Please complete all required patient fields.",
      );
      return;
    }

    final age =
    int.tryParse(ageText);

    if (age == null ||
        age <= 0 ||
        age > 130) {
      _showSnack(
        "Please enter a valid patient age.",
      );
      return;
    }

    // -------------------------------------------------------------------------
    // TRACK SUPABASE UPLOADS
    //
    // If something fails after uploading files, these paths are used to
    // clean up the uploaded Supabase objects.
    // -------------------------------------------------------------------------

    final List<String> uploadedStoragePaths = [];

    try {
      if (mounted) {
        setState(() {
          _isAddingPatient = true;
          _uploadProgress = 0;
        });
      }

      // -----------------------------------------------------------------------
      // GENERATE PATIENT ID
      // -----------------------------------------------------------------------

      final patientId =
      await _generatePatientId();

      // -----------------------------------------------------------------------
      // SUPABASE CLIENT
      // -----------------------------------------------------------------------

      final supabase =
          Supabase.instance.client;

      // -----------------------------------------------------------------------
      // PATIENT-WISE STORAGE DIRECTORY
      //
      // Every patient's files are isolated under their own folder.
      //
      // Example:
      //
      // patient-documents/
      //   patients/
      //     P 001/
      //       xray.jpg
      //       report.pdf
      //
      // -----------------------------------------------------------------------

      final patientStorageFolder =
          'patients/$patientId';

      final List<Map<String, dynamic>>
      uploadedDocs = [];

      final totalFiles =
          _selectedFiles.length;

      // -----------------------------------------------------------------------
      // UPLOAD DOCUMENTS / IMAGES TO SUPABASE
      // -----------------------------------------------------------------------

      if (totalFiles > 0) {
        for (
        int i = 0;
        i < _selectedFiles.length;
        i++
        ) {
          final file =
          _selectedFiles[i];

          final filePath =
              file.path;

          if (filePath == null ||
              filePath.isEmpty) {
            debugPrint(
              "Skipping ${file.name}: "
                  "file path unavailable.",
            );
            continue;
          }

          final fileExtension =
          (file.extension ?? '')
              .toLowerCase();

          final fileType =
              fileExtension;

          // -------------------------------------------------------------------
          // ORIGINAL LOCAL FILE
          // -------------------------------------------------------------------

          final File originalFile =
          File(filePath);

          File fileToUpload =
              originalFile;

          // -------------------------------------------------------------------
          // AI IMAGE PROCESSING
          //
          // Existing ML functionality remains unchanged.
          // Images are processed before being uploaded to Supabase.
          // -------------------------------------------------------------------

          final bool isImage =
          [
            'jpg',
            'jpeg',
            'png',
          ].contains(fileType);

          if (isImage &&
              _modelLoaded) {
            try {
              final detections =
              runModel(
                originalFile,
              );

              fileToUpload =
              await drawBoxes(
                originalFile,
                detections,
              );

              debugPrint(
                "AI annotation completed for "
                    "${file.name}",
              );
            } catch (e) {
              debugPrint(
                "MODEL ERROR ${file.name}: $e",
              );

              // Preserve the original image if
              // AI processing fails.
              fileToUpload =
                  originalFile;
            }
          }

          // -------------------------------------------------------------------
          // UNIQUE STORAGE FILE NAME
          // -------------------------------------------------------------------

          final safeFileName =
          _sanitizeStorageFileName(
            file.name,
          );

          final timestamp =
              DateTime.now()
                  .millisecondsSinceEpoch;

          final storagePath =
              '$patientStorageFolder/'
              '${timestamp}_$safeFileName';

          // -------------------------------------------------------------------
          // READ FILE
          // -------------------------------------------------------------------

          final fileBytes =
          await fileToUpload
              .readAsBytes();

          // -------------------------------------------------------------------
          // CONTENT TYPE
          // -------------------------------------------------------------------

          final contentType =
          _getMimeType(
            fileExtension,
          );

          // -------------------------------------------------------------------
          // UPLOAD TO SUPABASE STORAGE
          // -------------------------------------------------------------------

          await supabase
              .storage
              .from(
            _supabasePatientBucket,
          )
              .uploadBinary(
            storagePath,
            fileBytes,
            fileOptions:
            FileOptions(
              contentType:
              contentType,
              upsert: false,
            ),
          );

          // -------------------------------------------------------------------
          // REMEMBER UPLOADED PATH
          //
          // Used for rollback if Firestore fails.
          // -------------------------------------------------------------------

          uploadedStoragePaths
              .add(storagePath);

          // -------------------------------------------------------------------
          // GET SUPABASE PUBLIC URL
          //
          // This URL is stored in Firestore alongside the storage path.
          // -------------------------------------------------------------------

          final fileUrl =
          supabase
              .storage
              .from(
            _supabasePatientBucket,
          )
              .getPublicUrl(
            storagePath,
          );

          // -------------------------------------------------------------------
          // SAVE FILE REFERENCE
          // -------------------------------------------------------------------

          uploadedDocs.add(
            {
              'fileName':
              file.name,

              'fileType':
              fileType,

              'fileUrl':
              fileUrl,

              'storagePath':
              storagePath,

              'storageProvider':
              'supabase',

              'bucket':
              _supabasePatientBucket,

              'uploadedAt':
              DateTime.now()
                  .toIso8601String(),
            },
          );

          debugPrint(
            "SUPABASE UPLOAD SUCCESS: "
                "$storagePath",
          );

          // -------------------------------------------------------------------
          // UPDATE PROGRESS
          // -------------------------------------------------------------------

          if (mounted) {
            setState(() {
              _uploadProgress =
                  (i + 1) /
                      totalFiles;
            });
          }
        }
      }

      // -----------------------------------------------------------------------
      // CREATE PATIENT FIRESTORE RECORD
      //
      // Patient information continues to be stored in Firebase exactly as
      // before.
      //
      // Only the document/image references now point to Supabase.
      // -----------------------------------------------------------------------

      await FirebaseFirestore
          .instance
          .collection('patients')
          .add(
        {
          'patientId':
          patientId,

          'name':
          name,

          'age':
          age,

          'phone':
          phone,

          'email':
          email,

          'gender':
          _selectedGender,

          'assignedDoctor':
          _selectedDoctor,

          // ---------------------------------------------------------------
          // SUPABASE FILE REFERENCES
          // ---------------------------------------------------------------

          'documents':
          uploadedDocs,

          // ---------------------------------------------------------------
          // FIREBASE SERVER TIMESTAMP
          // ---------------------------------------------------------------

          'createdAt':
          FieldValue.serverTimestamp(),
        },
      );

      // -----------------------------------------------------------------------
      // SUCCESS
      // -----------------------------------------------------------------------

      _clearPatientForm();

      _showSnack(
        "Patient added successfully • $patientId",
        success: true,
      );
    } catch (e) {
      debugPrint(
        "ADD PATIENT ERROR: $e",
      );

      // -----------------------------------------------------------------------
      // ROLLBACK SUPABASE UPLOADS
      //
      // If files uploaded successfully but the Firebase patient record failed,
      // remove the orphaned Supabase files.
      // -----------------------------------------------------------------------

      await _deleteSupabaseFiles(
        uploadedStoragePaths,
      );

      if (!mounted) return;

      _showSnack(
        "Error adding patient: $e",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAddingPatient = false;
          _uploadProgress = 0;
        });
      }
    }
  }

// ===========================================================================
// CLEAR PATIENT FORM
// ===========================================================================

  void _clearPatientForm() {
    _nameController.clear();
    _ageController.clear();
    _phoneController.clear();
    _emailController.clear();

    if (!mounted) return;

    setState(() {
      _selectedGender = null;
      _selectedDoctor = null;
      _selectedFiles = [];
    });
  }

// ===========================================================================
// PATIENT FORM
// ===========================================================================

  Widget _buildAddPatientTab() {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final wide =
            constraints.maxWidth >=
                950;

        return _buildScrollablePage(
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 1180,
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(
                  22,
                ),
                child: wide
                    ? Row(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Expanded(
                      flex: 5,
                      child:
                      _buildPatientIntro(),
                    ),
                    const SizedBox(
                      width: 24,
                    ),
                    Expanded(
                      flex: 7,
                      child:
                      _buildPatientForm(),
                    ),
                  ],
                )
                    : _buildPatientForm(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPatientIntro() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        _sectionEyebrow(
          "PATIENT MANAGEMENT",
        ),
        const SizedBox(height: 10),
        Text(
          "Register a new\npatient",
          style:
          GoogleFonts.poppins(
            color: _white,
            fontSize: 34,
            height: 1.08,
            fontWeight:
            FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Create a complete clinical record and securely attach diagnostic documents for the care team.",
          style:
          GoogleFonts.inter(
            color: _secondaryText,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        _buildWorkflowStep(
          number: "01",
          icon:
          Icons.person_outline,
          title:
          "Patient information",
          description:
          "Identity, contact and demographic details.",
        ),
        const SizedBox(height: 14),
        _buildWorkflowStep(
          number: "02",
          icon: Icons
              .medical_services_outlined,
          title:
          "Assign surgeon",
          description:
          "Connect the patient to a registered surgeon.",
        ),
        const SizedBox(height: 14),
        _buildWorkflowStep(
          number: "03",
          icon: Icons
              .document_scanner_outlined,
          title:
          "Upload diagnostics",
          description:
          "Attach PDFs and images for clinical review.",
        ),
        const SizedBox(height: 28),
        Container(
          padding:
          const EdgeInsets.all(15),
          decoration:
          BoxDecoration(
            color: _cyan
                .withOpacity(0.035),
            borderRadius:
            BorderRadius.circular(16),
            border: Border.all(
              color: _cyan
                  .withOpacity(0.09),
            ),
          ),
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons
                    .auto_awesome_outlined,
                color: _cyan,
                size: 19,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  _modelLoaded
                      ? "AI image analysis is ready. Uploaded diagnostic images can be processed automatically before being securely stored."
                      : "AI image analysis is currently loading. Original images will be preserved if processing is unavailable.",
                  style:
                  GoogleFonts.inter(
                    color:
                    _secondaryText,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowStep({
    required String number,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration:
          BoxDecoration(
            color:
            Colors.white.withOpacity(
              0.035,
            ),
            borderRadius:
            BorderRadius.circular(13),
            border: Border.all(
              color:
              Colors.white.withOpacity(
                0.06,
              ),
            ),
          ),
          child: Icon(
            icon,
            color: _cyan,
            size: 20,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                "$number  $title",
                style:
                GoogleFonts.inter(
                  color: _white,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style:
                GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientForm() {
    return _glassCard(
      padding:
      const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(
                Icons
                    .person_add_alt_1_rounded,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    "Patient details",
                    style:
                    GoogleFonts.poppins(
                      color: _white,
                      fontSize: 18,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  Text(
                    "Required clinical information",
                    style:
                    GoogleFonts.inter(
                      color: _mutedText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 22),

          _buildFormField(
            controller:
            _nameController,
            label:
            "Patient Name",
            hint:
            "Enter patient's full name",
            icon:
            Icons.person_outline,
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              Expanded(
                child:
                _buildFormField(
                  controller:
                  _ageController,
                  label:
                  "Age",
                  hint:
                  "Years",
                  icon:
                  Icons
                      .calendar_today_outlined,
                  keyboardType:
                  TextInputType
                      .number,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child:
                _buildFormField(
                  controller:
                  _phoneController,
                  label:
                  "Phone",
                  hint:
                  "Contact number",
                  icon:
                  Icons.phone_outlined,
                  keyboardType:
                  TextInputType
                      .phone,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          _buildFormField(
            controller:
            _emailController,
            label:
            "Email Address",
            hint:
            "patient@example.com",
            icon:
            Icons.email_outlined,
            keyboardType:
            TextInputType
                .emailAddress,
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              Expanded(
                child:
                _buildDropdownField(
                  label:
                  "Gender",
                  icon:
                  Icons.wc_outlined,
                  value:
                  _selectedGender,
                  items:
                  const [
                    DropdownMenuItem(
                      value:
                      "Male",
                      child:
                      Text("Male"),
                    ),
                    DropdownMenuItem(
                      value:
                      "Female",
                      child:
                      Text("Female"),
                    ),
                    DropdownMenuItem(
                      value:
                      "Other",
                      child:
                      Text("Other"),
                    ),
                  ],
                  onChanged:
                      (value) {
                    setState(() {
                      _selectedGender =
                          value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child:
                _buildDoctorDropdown(),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _buildUploadArea(),

          if (_isAddingPatient) ...[
            const SizedBox(height: 16),
            _buildUploadProgress(),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width:
            double.infinity,
            height: 54,
            child:
            FilledButton.icon(
              onPressed:
              _isAddingPatient
                  ? null
                  : _addPatient,
              style:
              FilledButton.styleFrom(
                backgroundColor:
                _teal,
                disabledBackgroundColor:
                _teal.withOpacity(
                  0.4,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius
                      .circular(15),
                ),
              ),
              icon: _isAddingPatient
                  ? const SizedBox(
                width: 18,
                height: 18,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                  Colors.white,
                ),
              )
                  : const Icon(
                Icons
                    .person_add_alt_1_rounded,
                size: 19,
              ),
              label: Text(
                _isAddingPatient
                    ? "Processing patient record..."
                    : "Register Patient",
                style:
                GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

// ===========================================================================
// DOCTOR DROPDOWN
// ===========================================================================

  Widget _buildDoctorDropdown() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore
          .instance
          .collection('users')
          .where(
        'role',
        isEqualTo: 'surgeon',
      )
          .snapshots(),
      builder: (
          context,
          snapshot,
          ) {
        if (!snapshot.hasData) {
          return _buildDropdownLoading(
            "Assign Surgeon",
            Icons
                .medical_services_outlined,
          );
        }

        final doctors =
            snapshot.data!.docs;

        return _buildDropdownField(
          label:
          "Assign Surgeon",
          icon:
          Icons
              .medical_services_outlined,
          value:
          _selectedDoctor,
          items:
          doctors.map(
                (doc) {
              final data =
              doc.data()
              as Map<String,
                  dynamic>;

              final name =
                  data['name']
                      ?.toString() ??
                      "Unnamed";

              return DropdownMenuItem<
                  String>(
                value:
                doc.id,
                child:
                Text(
                  name,
                  overflow:
                  TextOverflow
                      .ellipsis,
                ),
              );
            },
          ).toList(),
          onChanged:
              (value) {
            setState(() {
              _selectedDoctor =
                  value;
            });
          },
        );
      },
    );
  }

// ===========================================================================
// DROPDOWN LOADING
// ===========================================================================

  Widget _buildDropdownLoading(
      String label,
      IconData icon,
      ) {
    return Container(
      height: 58,
      decoration:
      BoxDecoration(
        color:
        Colors.white.withOpacity(
          0.035,
        ),
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.065,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 15),
          Icon(
            icon,
            color: _mutedText,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style:
              GoogleFonts.inter(
                color: _mutedText,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(
            width: 15,
            height: 15,
            child:
            CircularProgressIndicator(
              strokeWidth: 1.5,
              color: _cyan,
            ),
          ),
          const SizedBox(width: 15),
        ],
      ),
    );
  }

// ===========================================================================
// UPLOAD AREA
// ===========================================================================

  Widget _buildUploadArea() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          "Diagnostic documents",
          style:
          GoogleFonts.inter(
            color: _white,
            fontSize: 12,
            fontWeight:
            FontWeight.w700,
          ),
        ),

        const SizedBox(height: 9),

        InkWell(
          borderRadius:
          BorderRadius.circular(
            15,
          ),
          onTap:
          _isAddingPatient
              ? null
              : _pickDocuments,
          child: Container(
            width:
            double.infinity,
            padding:
            const EdgeInsets.all(
              17,
            ),
            decoration:
            BoxDecoration(
              color:
              _cyan.withOpacity(
                0.025,
              ),
              borderRadius:
              BorderRadius.circular(
                15,
              ),
              border: Border.all(
                color:
                _cyan.withOpacity(
                  0.12,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration:
                  BoxDecoration(
                    color:
                    _cyan.withOpacity(
                      0.08,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),
                  child:
                  const Icon(
                    Icons
                        .cloud_upload_outlined,
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
                      Text(
                        "Select diagnostic files",
                        style:
                        GoogleFonts.inter(
                          color: _white,
                          fontSize: 11.5,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                      const SizedBox(
                          height: 3),
                      Text(
                        "PDF, PNG, JPG or JPEG • Stored securely in Supabase",
                        style:
                        GoogleFonts.inter(
                          color:
                          _mutedText,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons
                      .arrow_forward_ios_rounded,
                  color: _mutedText,
                  size: 13,
                ),
              ],
            ),
          ),
        ),

        if (_selectedFiles
            .isNotEmpty) ...[
          const SizedBox(height: 10),

          ..._selectedFiles.map(
                (file) =>
                _buildSelectedFile(
                  file,
                ),
          ),
        ],
      ],
    );
  }

// ===========================================================================
// SELECTED FILE
// ===========================================================================

  Widget _buildSelectedFile(
      PlatformFile file,
      ) {
    final extension =
    (file.extension ?? '')
        .toLowerCase();

    final isPdf =
        extension == 'pdf';

    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 6,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration:
      BoxDecoration(
        color:
        Colors.white.withOpacity(
          0.025,
        ),
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.05,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPdf
                ? Icons
                .picture_as_pdf_outlined
                : Icons.image_outlined,
            color:
            isPdf
                ? _danger
                : _cyan,
            size: 17,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style:
              GoogleFonts.inter(
                color:
                _secondaryText,
                fontSize: 10.5,
              ),
            ),
          ),

          InkWell(
            onTap:
            _isAddingPatient
                ? null
                : () {
              setState(() {
                _selectedFiles
                    .remove(
                  file,
                );
              });
            },
            child:
            const Icon(
              Icons.close_rounded,
              color: _mutedText,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

// ===========================================================================
// UPLOAD PROGRESS
// ===========================================================================

  Widget _buildUploadProgress() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
          MainAxisAlignment
              .spaceBetween,
          children: [
            Text(
              "Uploading to secure storage",
              style:
              GoogleFonts.inter(
                color:
                _secondaryText,
                fontSize: 10,
                fontWeight:
                FontWeight.w600,
              ),
            ),
            Text(
              "${(_uploadProgress * 100).round()}%",
              style:
              GoogleFonts.inter(
                color: _cyan,
                fontSize: 10,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ],
        ),

        const SizedBox(height: 7),

        ClipRRect(
          borderRadius:
          BorderRadius.circular(
            10,
          ),
          child:
          LinearProgressIndicator(
            value: _selectedFiles
                .isEmpty
                ? null
                : _uploadProgress,
            minHeight: 5,
            backgroundColor:
            Colors.white
                .withOpacity(
              0.06,
            ),
            color: _cyan,
          ),
        ),
      ],
    );
  }


  // ===========================================================================
  // DOCTOR MANAGEMENT
  // ===========================================================================

  Future<void> _showAddDoctorDialog() async {
    final nameController =
    TextEditingController();

    final emailController =
    TextEditingController();

    final specializationController =
    TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return _buildProfessionalDialog(
          title: "Add New Doctor",
          icon: Icons.medical_services_outlined,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(
                nameController,
                "Full Name",
                Icons.person_outline,
              ),
              const SizedBox(height: 14),
              _dialogField(
                emailController,
                "Email Address",
                Icons.email_outlined,
                keyboardType:
                TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _dialogField(
                specializationController,
                "Specialization",
                Icons.medical_information_outlined,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext),
              child: Text(
                "Cancel",
                style: GoogleFonts.inter(
                  color: _mutedText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
              ),
              onPressed: () async {
                final name =
                nameController.text.trim();

                final email =
                emailController.text.trim();

                final specialization =
                specializationController
                    .text
                    .trim();

                if (name.isEmpty ||
                    email.isEmpty ||
                    specialization.isEmpty) {
                  _showSnack(
                    "Please complete all doctor fields.",
                  );
                  return;
                }

                Navigator.pop(dialogContext);

                await _createDoctorAccount(
                  name,
                  email,
                  specialization,
                );
              },
              child: Text(
                "Create Doctor",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    specializationController.dispose();
  }

  Future<void> _createDoctorAccount(
      String name,
      String email,
      String specialization,
      ) async {
    FirebaseApp? tempApp;

    try {
      tempApp =
      await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options:
        Firebase.app().options,
      );

      final tempAuth =
      FirebaseAuth.instanceFor(
        app: tempApp,
      );

      final password =
          "doc@${DateTime.now().millisecondsSinceEpoch}";

      final newDoctor =
      await tempAuth
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid =
          newDoctor.user!.uid;

      // Store doctor in the existing doctors collection.
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .set(
        {
          'name': name,
          'email': email,
          'specialization':
          specialization,
          'createdAt':
          Timestamp.now(),
          'generatedPassword':
          password,
        },
      );

      // Also create the user profile used
      // throughout the application.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
        {
          'uid': uid,
          'name': name,
          'email': email,
          'specialization':
          specialization,
          'role': 'surgeon',
          'createdAt':
          Timestamp.now(),
        },
      );

      await tempApp.delete();

      tempApp = null;

      if (!mounted) return;

      _showSnack(
        "Doctor created successfully. Generated password: $password",
        success: true,
        duration:
        const Duration(seconds: 7),
      );
    } catch (e) {
      if (tempApp != null) {
        try {
          await tempApp.delete();
        } catch (_) {}
      }

      _showSnack(
        "Error adding doctor: $e",
      );
    }
  }

  Future<void> _deleteDoctor(
      String docId,
      ) async {
    final confirmed =
    await _showDeleteConfirmation(
      title: "Delete Doctor?",
      message:
      "This will remove the doctor's profile from the doctor records.",
    );

    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(docId)
          .delete();

      _showSnack(
        "Doctor deleted successfully.",
        success: true,
      );
    } catch (e) {
      _showSnack(
        "Error deleting doctor: $e",
      );
    }
  }

  Future<void> _deletePatient(
      DocumentSnapshot doc,
      ) async {
    final data =
        doc.data() as Map<String, dynamic>? ??
            {};

    final name =
        data['name']?.toString() ??
            'this patient';

    final confirmed =
    await _showDeleteConfirmation(
      title: "Delete Patient?",
      message:
      "Are you sure you want to permanently remove $name and the associated patient record?",
    );

    if (!confirmed) return;

    try {
      await doc.reference.delete();

      _showSnack(
        "Patient deleted successfully.",
        success: true,
      );
    } catch (e) {
      _showSnack(
        "Error deleting patient: $e",
      );
    }
  }

  // ===========================================================================
  // MAIN BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          _buildAnimatedBackground(),

          SafeArea(
            child: FadeTransition(
              opacity: _pageFade,
              child: SlideTransition(
                position: _pageSlide,
                child: Column(
                  children: [
                    _buildTopBar(),
                    _buildNavigation(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAddPatientTab(),
                          _buildRegisteredPatientsTab(),
                          _buildManageDoctors(),
                          _buildAnalytics(),
                          _buildSettings(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ANIMATED BACKGROUND
  // ===========================================================================

  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          final value =
              _backgroundController.value;

          return Stack(
            children: [
              Container(
                decoration:
                const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _background,
                      _backgroundMid,
                      _background,
                    ],
                  ),
                ),
              ),

              Positioned(
                left: -180 +
                    (value * 70),
                top: -190,
                child: _ambientOrb(
                  440,
                  _teal,
                ),
              ),

              Positioned(
                right: -190 -
                    (value * 60),
                bottom: -200,
                child: _ambientOrb(
                  450,
                  _cyan,
                ),
              ),

              Positioned(
                right: 100,
                top: 80 +
                    math.sin(
                      value * math.pi * 2,
                    ) *
                        30,
                child: _ambientOrb(
                  180,
                  _purple,
                ),
              ),

              Positioned.fill(
                child: CustomPaint(
                  painter:
                  _MedicalGridPainter(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ambientOrb(
      double size,
      Color color,
      ) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration:
        BoxDecoration(
          shape: BoxShape.circle,
          gradient:
          RadialGradient(
            colors: [
              color.withOpacity(0.13),
              color.withOpacity(0.035),
              Colors.transparent,
            ],
            stops: const [
              0,
              0.55,
              1,
            ],
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
      padding: const EdgeInsets.fromLTRB(
        22,
        18,
        22,
        8,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              );
            },
            child: Container(
              width: 48,
              height: 48,
              decoration:
              BoxDecoration(
                borderRadius:
                BorderRadius.circular(
                  15,
                ),
                gradient:
                const LinearGradient(
                  begin:
                  Alignment.topLeft,
                  end:
                  Alignment.bottomRight,
                  colors: [
                    _teal,
                    _cyan,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                    _cyan.withOpacity(
                      0.18,
                    ),
                    blurRadius: 25,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_hospital_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  "SurgiAssist",
                  style:
                  GoogleFonts.poppins(
                    color: _white,
                    fontSize: 21,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    -0.5,
                  ),
                ),
                Text(
                  "Clinical Administration",
                  style:
                  GoogleFonts.inter(
                    color:
                    _secondaryText,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          _buildModelStatus(),

          const SizedBox(width: 10),

          _buildProfileMiniButton(),
        ],
      ),
    );
  }

  Widget _buildModelStatus() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration:
      BoxDecoration(
        color: Colors.white
            .withOpacity(0.035),
        borderRadius:
        BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color: (_modelLoaded
              ? _success
              : _warning)
              .withOpacity(0.14),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
            BoxDecoration(
              color: _modelLoaded
                  ? _success
                  : _warning,
              shape:
              BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _modelLoaded
                ? "AI READY"
                : "AI LOADING",
            style:
            GoogleFonts.inter(
              color:
              _modelLoaded
                  ? _success
                  : _warning,
              fontSize: 9,
              fontWeight:
              FontWeight.w800,
              letterSpacing:
              0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMiniButton() {
    final user =
        FirebaseAuth.instance
            .currentUser;

    return InkWell(
      borderRadius:
      BorderRadius.circular(
        14,
      ),
      onTap: () {
        _tabController.animateTo(4);
      },
      child: Container(
        width: 43,
        height: 43,
        decoration:
        BoxDecoration(
          color: Colors.white
              .withOpacity(0.045),
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.07),
          ),
        ),
        child: user?.photoURL != null
            ? ClipRRect(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          child: Image.network(
            user!.photoURL!,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) =>
            const Icon(
              Icons.person_outline,
              color:
              _secondaryText,
              size: 20,
            ),
          ),
        )
            : const Icon(
          Icons.person_outline,
          color: _secondaryText,
          size: 20,
        ),
      ),
    );
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        4,
        18,
        12,
      ),
      child: Container(
        height: 62,
        decoration:
        BoxDecoration(
          color:
          Colors.white.withOpacity(
            0.025,
          ),
          borderRadius:
          BorderRadius.circular(
            18,
          ),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.055),
          ),
        ),
        child: TabBar(
          controller:
          _tabController,
          indicatorSize:
          TabBarIndicatorSize.tab,
          indicatorPadding:
          const EdgeInsets.all(6),
          dividerColor:
          Colors.transparent,
          indicator:
          BoxDecoration(
            gradient:
            const LinearGradient(
              colors: [
                _teal,
                Color(0xFF0A6076),
              ],
            ),
            borderRadius:
            BorderRadius.circular(
              13,
            ),
            boxShadow: [
              BoxShadow(
                color: _teal
                    .withOpacity(0.22),
                blurRadius: 18,
              ),
            ],
          ),
          labelColor:
          Colors.white,
          unselectedLabelColor:
          _mutedText,
          labelStyle:
          GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w700,
          ),
          unselectedLabelStyle:
          GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight:
            FontWeight.w500,
          ),
          tabs: const [
            Tab(
              icon: Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
              ),
              text: "Add Patient",
            ),
            Tab(
              icon: Icon(
                Icons.people_alt_outlined,
                size: 18,
              ),
              text: "Patients",
            ),
            Tab(
              icon: Icon(
                Icons.medical_services_outlined,
                size: 18,
              ),
              text: "Doctors",
            ),
            Tab(
              icon: Icon(
                Icons.analytics_outlined,
                size: 18,
              ),
              text: "Analytics",
            ),
            Tab(
              icon: Icon(
                Icons.settings_outlined,
                size: 18,
              ),
              text: "Settings",
            ),
          ],
        ),
      ),
    );
  }


  // ===========================================================================
  // PATIENTS
  // ===========================================================================

  Widget _buildRegisteredPatientsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .orderBy(
        'createdAt',
        descending: true,
      )
          .snapshots(),
      builder: (
          context,
          snapshot,
          ) {
        if (snapshot.connectionState ==
            ConnectionState
                .waiting &&
            !snapshot.hasData) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            "Unable to load patient records.",
          );
        }

        final patients =
            snapshot.data?.docs ??
                [];

        final filtered =
        patients.where(
              (doc) {
            if (_patientSearchQuery
                .isEmpty) {
              return true;
            }

            final data =
            doc.data()
            as Map<String,
                dynamic>;

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

            final phone =
                data['phone']
                    ?.toString()
                    .toLowerCase() ??
                    '';

            return name.contains(
              _patientSearchQuery,
            ) ||
                patientId.contains(
                  _patientSearchQuery,
                ) ||
                phone.contains(
                  _patientSearchQuery,
                );
          },
        ).toList();

        return _buildScrollablePage(
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 1200,
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(
                  22,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    _buildPageHeader(
                      eyebrow:
                      "PATIENT REGISTRY",
                      title:
                      "Patient records",
                      description:
                      "Review, search and manage registered clinical records.",
                      trailing:
                      _buildCountBadge(
                        patients.length,
                        "TOTAL",
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPatientKpis(
                      patients,
                    ),
                    const SizedBox(height: 18),
                    _buildSearchField(
                      hint:
                      "Search by patient name, ID or phone...",
                      controller:
                      _patientSearchController,
                    ),
                    const SizedBox(height: 16),
                    if (patients.isEmpty)
                      _buildEmptyState(
                        icon: Icons
                            .people_outline_rounded,
                        title:
                        "No patients registered",
                        description:
                        "Patient records will appear here once they are added.",
                      )
                    else if (filtered.isEmpty)
                      _buildEmptyState(
                        icon: Icons
                            .search_off_rounded,
                        title:
                        "No matching patients",
                        description:
                        "Try a different patient name, ID or phone number.",
                      )
                    else
                      ...filtered.map(
                        _buildPatientCard,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPatientKpis(
      List<QueryDocumentSnapshot> patients,
      ) {
    int documents = 0;
    int male = 0;
    int female = 0;

    for (final patient in patients) {
      final data =
      patient.data()
      as Map<String,
          dynamic>;

      final docs =
      data['documents'];

      if (docs is List) {
        documents += docs.length;
      }

      final gender =
      data['gender']
          ?.toString()
          .toLowerCase();

      if (gender == 'male') {
        male++;
      } else if (gender == 'female') {
        female++;
      }
    }

    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final compact =
            constraints.maxWidth <
                700;

        final cards = [
          _buildMiniKpi(
            "Patients",
            patients.length
                .toString(),
            Icons.people_alt_outlined,
            _cyan,
          ),
          _buildMiniKpi(
            "Documents",
            documents.toString(),
            Icons
                .description_outlined,
            _purple,
          ),
          _buildMiniKpi(
            "Male",
            male.toString(),
            Icons.male_outlined,
            _teal,
          ),
          _buildMiniKpi(
            "Female",
            female.toString(),
            Icons.female_outlined,
            _success,
          ),
        ];

        if (compact) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map(
                  (card) =>
                  SizedBox(
                    width:
                    (constraints.maxWidth -
                        10) /
                        2,
                    child: card,
                  ),
            )
                .toList(),
          );
        }

        return Row(
          children: cards
              .map(
                (card) =>
                Expanded(
                  child: Padding(
                    padding:
                    const EdgeInsets
                        .only(
                      right: 10,
                    ),
                    child: card,
                  ),
                ),
          )
              .toList(),
        );
      },
    );
  }

  Widget _buildMiniKpi(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      height: 82,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration:
      BoxDecoration(
        color: Colors.white
            .withOpacity(0.035),
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.055),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration:
            BoxDecoration(
              color: color
                  .withOpacity(0.09),
              borderRadius:
              BorderRadius.circular(
                12,
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              Text(
                value,
                style:
                GoogleFonts.poppins(
                  color: _white,
                  fontSize: 19,
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
              Text(
                title,
                style:
                GoogleFonts.inter(
                  color:
                  _mutedText,
                  fontSize: 9.5,
                  fontWeight:
                  FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(
      DocumentSnapshot doc,
      ) {
    final data =
    doc.data()
    as Map<String,
        dynamic>;

    final name =
        data['name']
            ?.toString() ??
            'Unknown patient';

    final patientId =
        data['patientId']
            ?.toString() ??
            doc.id;

    final age =
        data['age']
            ?.toString() ??
            'N/A';

    final gender =
        data['gender']
            ?.toString() ??
            'N/A';

    final doctor =
        data['assignedDoctor']
            ?.toString() ??
            'N/A';

    final documents =
    data['documents'];

    final documentCount =
    documents is List
        ? documents.length
        : 0;

    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PatientHistoryPage(
                    patientId: doc.id,
                    patientData: data,
                  ),
            ),
          );
        },
        child: Container(
          padding:
          const EdgeInsets.all(
            15,
          ),
          decoration:
          BoxDecoration(
            color: Colors.white
                .withOpacity(0.032),
            borderRadius:
            BorderRadius.circular(
              17,
            ),
            border: Border.all(
              color: Colors.white
                  .withOpacity(0.055),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration:
                BoxDecoration(
                  gradient:
                  const LinearGradient(
                    colors: [
                      _teal,
                      _cyan,
                    ],
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    15,
                  ),
                ),
                child: const Icon(
                  Icons
                      .person_outline_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            GoogleFonts.inter(
                              color:
                              _white,
                              fontSize:
                              13,
                              fontWeight:
                              FontWeight
                                  .w700,
                            ),
                          ),
                        ),
                        const SizedBox(
                            width: 8),
                        _patientIdBadge(
                          patientId,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _patientMeta(
                          Icons
                              .calendar_today_outlined,
                          "Age $age",
                        ),
                        _patientMeta(
                          Icons.wc_outlined,
                          gender,
                        ),
                        _patientMeta(
                          Icons
                              .description_outlined,
                          "$documentCount docs",
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Assigned surgeon: $doctor",
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      GoogleFonts.inter(
                        color:
                        _mutedText,
                        fontSize:
                        9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip:
                "Delete patient",
                onPressed: () =>
                    _deletePatient(
                      doc,
                    ),
                icon: const Icon(
                  Icons
                      .delete_outline_rounded,
                  color: _danger,
                  size: 20,
                ),
              ),
              const Icon(
                Icons
                    .arrow_forward_ios_rounded,
                color: _mutedText,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patientIdBadge(
      String id,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration:
      BoxDecoration(
        color: _cyan
            .withOpacity(0.06),
        borderRadius:
        BorderRadius.circular(
          7,
        ),
      ),
      child: Text(
        id,
        style:
        GoogleFonts.inter(
          color: _cyan,
          fontSize: 8.5,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }

  Widget _patientMeta(
      IconData icon,
      String text,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: _mutedText,
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style:
          GoogleFonts.inter(
            color:
            _secondaryText,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // DOCTORS
  // ===========================================================================

  Widget _buildManageDoctors() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where(
        'role',
        isEqualTo: 'surgeon',
      )
          .snapshots(),
      builder: (
          context,
          snapshot,
          ) {
        if (snapshot.connectionState ==
            ConnectionState
                .waiting &&
            !snapshot.hasData) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState(
            "Unable to load doctor records.",
          );
        }

        final doctors =
            snapshot.data?.docs ??
                [];

        return _buildScrollablePage(
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 1200,
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(
                  22,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    _buildPageHeader(
                      eyebrow:
                      "CLINICAL TEAM",
                      title:
                      "Manage doctors",
                      description:
                      "Manage surgeons with access to the SurgiAssist clinical workspace.",
                      trailing:
                      FilledButton.icon(
                        onPressed:
                        _showAddDoctorDialog,
                        style:
                        FilledButton.styleFrom(
                          backgroundColor:
                          _teal,
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 15,
                            vertical: 12,
                          ),
                          shape:
                          RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius
                                .circular(
                              12,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          Icons
                              .person_add_alt_1_rounded,
                          size: 17,
                        ),
                        label: Text(
                          "Add Doctor",
                          style:
                          GoogleFonts
                              .inter(
                            fontSize:
                            10.5,
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildTeamStat(
                          "Registered",
                          doctors.length
                              .toString(),
                          Icons
                              .medical_services_outlined,
                          _cyan,
                        ),
                        const SizedBox(
                            width: 10),
                        _buildTeamStat(
                          "Clinical access",
                          doctors.isEmpty
                              ? "0%"
                              : "100%",
                          Icons
                              .verified_user_outlined,
                          _success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (doctors.isEmpty)
                      _buildEmptyState(
                        icon: Icons
                            .medical_services_outlined,
                        title:
                        "No doctors registered",
                        description:
                        "Add a doctor to begin assigning surgeons to patients.",
                      )
                    else
                      ...doctors.map(
                        _buildDoctorCard,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeamStat(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Expanded(
      child: Container(
        height: 76,
        padding:
        const EdgeInsets.all(
          13,
        ),
        decoration:
        BoxDecoration(
          color: Colors.white
              .withOpacity(0.035),
          borderRadius:
          BorderRadius.circular(
            15,
          ),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.055),
          ),
        ),
        child: Row(
          children: [
            _iconBox(
              icon,
              color: color,
              size: 39,
            ),
            const SizedBox(width: 11),
            Column(
              mainAxisAlignment:
              MainAxisAlignment
                  .center,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  value,
                  style:
                  GoogleFonts.poppins(
                    color: _white,
                    fontSize: 18,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorCard(
      DocumentSnapshot doc,
      ) {
    final data =
    doc.data()
    as Map<String,
        dynamic>;

    final name =
        data['name']
            ?.toString() ??
            'Unnamed Doctor';

    final email =
        data['email']
            ?.toString() ??
            'N/A';

    final specialization =
        data['specialization']
            ?.toString() ??
            'N/A';

    final phone =
    data['phone']
        ?.toString();

    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: Container(
        padding:
        const EdgeInsets.all(
          16,
        ),
        decoration:
        BoxDecoration(
          color: Colors.white
              .withOpacity(0.032),
          borderRadius:
          BorderRadius.circular(
            17,
          ),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.055),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 51,
              height: 51,
              decoration:
              BoxDecoration(
                gradient:
                const LinearGradient(
                  colors: [
                    _teal,
                    _cyan,
                  ],
                ),
                borderRadius:
                BorderRadius.circular(
                  16,
                ),
              ),
              child: const Icon(
                Icons
                    .medical_services_outlined,
                color: Colors.white,
                size: 24,
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
                    name,
                    style:
                    GoogleFonts.inter(
                      color: _white,
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _doctorMeta(
                        Icons
                            .medical_information_outlined,
                        specialization,
                      ),
                      _doctorMeta(
                        Icons
                            .email_outlined,
                        email,
                      ),
                      if (phone != null)
                        _doctorMeta(
                          Icons
                              .phone_outlined,
                          phone,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip:
              "Delete doctor",
              onPressed: () =>
                  _deleteDoctor(
                    doc.id,
                  ),
              icon: const Icon(
                Icons
                    .delete_outline_rounded,
                color: _danger,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doctorMeta(
      IconData icon,
      String value,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: _mutedText,
          size: 12,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints:
          const BoxConstraints(
            maxWidth: 230,
          ),
          child: Text(
            value,
            overflow:
            TextOverflow.ellipsis,
            style:
            GoogleFonts.inter(
              color:
              _secondaryText,
              fontSize: 9,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ANALYTICS
  // ===========================================================================

  Widget _buildAnalytics() {
    final patientsStream =
    FirebaseFirestore.instance
        .collection('patients')
        .snapshots();

    final doctorsStream =
    FirebaseFirestore.instance
        .collection('users')
        .where(
      'role',
      isEqualTo: 'surgeon',
    )
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: patientsStream,
      builder: (
          context,
          patientSnapshot,
          ) {
        return StreamBuilder<QuerySnapshot>(
          stream: doctorsStream,
          builder: (
              context,
              doctorSnapshot,
              ) {
            if (!patientSnapshot
                .hasData ||
                !doctorSnapshot
                    .hasData) {
              return _buildLoadingState();
            }

            final patients =
                patientSnapshot
                    .data!
                    .docs;

            final doctors =
                doctorSnapshot
                    .data!
                    .docs;

            final analytics =
            _calculateAnalytics(
              patients,
              doctors,
            );

            return _buildScrollablePage(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 1250,
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets
                        .all(
                      22,
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        _buildPageHeader(
                          eyebrow:
                          "SYSTEM INTELLIGENCE",
                          title:
                          "Clinical analytics",
                          description:
                          "Real-time operational insight from your SurgiAssist records.",
                          trailing:
                          _buildLiveBadge(),
                        ),
                        const SizedBox(
                            height: 22),

                        _buildAnalyticsKpis(
                          analytics,
                        ),

                        const SizedBox(
                            height: 18),

                        LayoutBuilder(
                          builder: (
                              context,
                              constraints,
                              ) {
                            final wide =
                                constraints
                                    .maxWidth >=
                                    850;

                            if (wide) {
                              return Row(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child:
                                    _buildPatientGrowthChart(
                                      analytics,
                                    ),
                                  ),
                                  const SizedBox(
                                      width: 16),
                                  Expanded(
                                    flex: 4,
                                    child:
                                    _buildGenderChart(
                                      analytics,
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                _buildPatientGrowthChart(
                                  analytics,
                                ),
                                const SizedBox(
                                    height: 16),
                                _buildGenderChart(
                                  analytics,
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(
                            height: 16),

                        LayoutBuilder(
                          builder: (
                              context,
                              constraints,
                              ) {
                            final wide =
                                constraints
                                    .maxWidth >=
                                    850;

                            if (wide) {
                              return Row(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child:
                                    _buildMonthlyBarChart(
                                      analytics,
                                    ),
                                  ),
                                  const SizedBox(
                                      width: 16),
                                  Expanded(
                                    flex: 4,
                                    child:
                                    _buildDoctorWorkload(
                                      analytics,
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                _buildMonthlyBarChart(
                                  analytics,
                                ),
                                const SizedBox(
                                    height: 16),
                                _buildDoctorWorkload(
                                  analytics,
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(
                            height: 18),

                        _buildAnalyticsInsight(
                          analytics,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _calculateAnalytics(
      List<QueryDocumentSnapshot> patients,
      List<QueryDocumentSnapshot> doctors,
      ) {
    int male = 0;
    int female = 0;
    int other = 0;
    int totalDocuments = 0;

    final Map<int, int>
    monthlyPatients = {};

    final Map<String, int>
    doctorAssignments = {};

    for (final patient in patients) {
      final data =
      patient.data()
      as Map<String,
          dynamic>;

      final gender =
      data['gender']
          ?.toString()
          .toLowerCase();

      if (gender == 'male') {
        male++;
      } else if (gender ==
          'female') {
        female++;
      } else {
        other++;
      }

      final documents =
      data['documents'];

      if (documents is List) {
        totalDocuments +=
            documents.length;
      }

      DateTime? created;

      final timestamp =
      data['createdAt'];

      if (timestamp is Timestamp) {
        created =
            timestamp.toDate();
      }

      if (created != null) {
        final key =
            created.year * 12 +
                created.month;

        monthlyPatients[key] =
            (monthlyPatients[key] ??
                0) +
                1;
      }

      final doctor =
      data['assignedDoctor']
          ?.toString();

      if (doctor != null &&
          doctor.isNotEmpty) {
        doctorAssignments[doctor] =
            (doctorAssignments[
            doctor] ??
                0) +
                1;
      }
    }

    return {
      'totalPatients':
      patients.length,
      'totalDoctors':
      doctors.length,
      'totalDocuments':
      totalDocuments,
      'male': male,
      'female': female,
      'other': other,
      'monthlyPatients':
      monthlyPatients,
      'doctorAssignments':
      doctorAssignments,
      'patients':
      patients,
      'doctors':
      doctors,
    };
  }

// ===========================================================================
// CLINICAL ANALYTICS — KPI CARDS
// ===========================================================================

  Widget _buildAnalyticsKpis(
      Map<String, dynamic> data,
      ) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final double availableWidth =
            constraints.maxWidth;

        final bool compact =
            availableWidth < 700;

        final cards = [
          _buildAnalyticsKpi(
            "Total Patients",
            "${data['totalPatients']}",
            Icons.people_alt_outlined,
            _cyan,
            "Registered records",
            compact: compact,
          ),

          _buildAnalyticsKpi(
            "Surgeons",
            "${data['totalDoctors']}",
            Icons.medical_services_outlined,
            _teal,
            "Clinical team",
            compact: compact,
          ),

          _buildAnalyticsKpi(
            "Documents",
            "${data['totalDocuments']}",
            Icons.description_outlined,
            _purple,
            "Uploaded files",
            compact: compact,
          ),

          _buildAnalyticsKpi(
            "AI Status",
            _modelLoaded
                ? "READY"
                : "LOADING",
            Icons.auto_awesome_outlined,
            _modelLoaded
                ? _success
                : _warning,
            "Inference engine",
            compact: compact,
          ),
        ];

        // -----------------------------------------------------------------------
        // COMPACT / TABLET LAYOUT
        // -----------------------------------------------------------------------

        if (compact) {
          final double cardWidth =
              (availableWidth - 10) / 2;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards.map(
                  (card) {
                return SizedBox(
                  width: cardWidth,
                  child: card,
                );
              },
            ).toList(),
          );
        }

        // -----------------------------------------------------------------------
        // DESKTOP LAYOUT
        // -----------------------------------------------------------------------

        return Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: List.generate(
            cards.length,
                (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right:
                    index == cards.length - 1
                        ? 0
                        : 10,
                  ),
                  child: cards[index],
                ),
              );
            },
          ),
        );
      },
    );
  }


// ===========================================================================
// ANALYTICS KPI CARD
// ===========================================================================

  Widget _buildAnalyticsKpi(
      String title,
      String value,
      IconData icon,
      Color color,
      String subtitle, {
        bool compact = false,
      }) {
    return AnimatedContainer(
      duration:
      const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,

      // -------------------------------------------------------------------------
      // IMPORTANT:
      // A slightly more generous fixed height is used, but the internal layout
      // is horizontal so text can never push beyond the bottom of the card.
      // -------------------------------------------------------------------------

      height: compact ? 92 : 96,

      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 11 : 12,
      ),

      decoration: BoxDecoration(
        color: Colors.white.withOpacity(
          0.035,
        ),
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(
            0.10,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(
              0.035,
            ),
            blurRadius: 20,
            offset:
            const Offset(0, 8),
          ),
        ],
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.center,
        children: [

          // ---------------------------------------------------------------------
          // KPI ICON
          // ---------------------------------------------------------------------

          Container(
            width: compact ? 38 : 42,
            height: compact ? 38 : 42,
            decoration: BoxDecoration(
              color: color.withOpacity(
                0.085,
              ),
              borderRadius:
              BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(
                  0.08,
                ),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: compact ? 19 : 21,
            ),
          ),

          SizedBox(
            width: compact ? 10 : 12,
          ),

          // ---------------------------------------------------------------------
          // KPI CONTENT
          // ---------------------------------------------------------------------

          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              mainAxisSize:
              MainAxisSize.min,
              children: [

                // ---------------------------------------------------------------
                // VALUE + STATUS INDICATOR
                // ---------------------------------------------------------------

                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.center,
                  children: [

                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style:
                        GoogleFonts.poppins(
                          color: _white,
                          fontSize:
                          compact ? 18 : 20,
                          fontWeight:
                          FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 6,
                    ),

                    // Small live/status indicator.
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                      BoxDecoration(
                        color: color,
                        shape:
                        BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                            color.withOpacity(
                              0.35,
                            ),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 5,
                ),

                // ---------------------------------------------------------------
                // TITLE
                // ---------------------------------------------------------------

                Text(
                  title,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.inter(
                    color:
                    _secondaryText,
                    fontSize:
                    compact ? 9.5 : 10,
                    fontWeight:
                    FontWeight.w700,
                    height: 1.05,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                // ---------------------------------------------------------------
                // SUBTITLE
                // ---------------------------------------------------------------

                Text(
                  subtitle,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize:
                    compact ? 8 : 8.5,
                    fontWeight:
                    FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildPatientGrowthChart(
      Map<String, dynamic> data,
      ) {
    final Map<int, int>
    monthly =
    data['monthlyPatients']
    as Map<int, int>;

    final now = DateTime.now();

    final List<FlSpot> spots = [];

    double maxY = 0;

    for (int i = 5; i >= 0; i--) {
      final date =
      DateTime(
        now.year,
        now.month - i,
      );

      final key =
          date.year * 12 +
              date.month;

      final count =
          monthly[key] ?? 0;

      if (count > maxY) {
        maxY = count.toDouble();
      }

      spots.add(
        FlSpot(
          (5 - i).toDouble(),
          count.toDouble(),
        ),
      );
    }

    if (maxY < 5) {
      maxY = 5;
    }

    return _chartCard(
      title: "Patient growth",
      subtitle:
      "Registrations over the last six months",
      icon: Icons
          .trending_up_rounded,
      child: SizedBox(
        height: 265,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 5,
            minY: 0,
            maxY: maxY + 1,
            gridData:
            FlGridData(
              show: true,
              drawVerticalLine:
              false,
              horizontalInterval:
              maxY <= 5
                  ? 1
                  : maxY / 4,
              getDrawingHorizontalLine:
                  (value) =>
                  FlLine(
                    color: Colors.white
                        .withOpacity(
                      0.055,
                    ),
                    strokeWidth: 1,
                  ),
            ),
            borderData:
            FlBorderData(
              show: false,
            ),
            titlesData:
            FlTitlesData(
              topTitles:
              const AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  false,
                ),
              ),
              rightTitles:
              const AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  false,
                ),
              ),
              leftTitles:
              AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles: true,
                  reservedSize:
                  30,
                  interval:
                  maxY <= 5
                      ? 1
                      : maxY / 4,
                  getTitlesWidget:
                      (value, meta) {
                    return Text(
                      value
                          .round()
                          .toString(),
                      style:
                      GoogleFonts
                          .inter(
                        color:
                        _mutedText,
                        fontSize:
                        8,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles:
              AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  true,
                  reservedSize:
                  30,
                  getTitlesWidget:
                      (value, meta) {
                    final index =
                    value.round();

                    if (index <
                        0 ||
                        index >
                            5) {
                      return const SizedBox
                          .shrink();
                    }

                    final date =
                    DateTime(
                      now.year,
                      now.month -
                          (5 -
                              index),
                    );

                    const months = [
                      'Jan',
                      'Feb',
                      'Mar',
                      'Apr',
                      'May',
                      'Jun',
                      'Jul',
                      'Aug',
                      'Sep',
                      'Oct',
                      'Nov',
                      'Dec',
                    ];

                    return Padding(
                      padding:
                      const EdgeInsets
                          .only(
                        top: 8,
                      ),
                      child: Text(
                        months[
                        date.month -
                            1],
                        style:
                        GoogleFonts
                            .inter(
                          color:
                          _mutedText,
                          fontSize:
                          8.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData:
            LineTouchData(
              enabled: true,
              touchTooltipData:
              LineTouchTooltipData(
                getTooltipItems:
                    (spots) {
                  return spots
                      .map(
                        (spot) =>
                        LineTooltipItem(
                          "${spot.y.round()} patients",
                          GoogleFonts
                              .inter(
                            color:
                            Colors.white,
                            fontSize:
                            10,
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                  )
                      .toList();
                },
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness:
                0.28,
                barWidth: 3,
                color: _cyan,
                dotData:
                FlDotData(
                  show: true,
                  getDotPainter:
                      (
                      spot,
                      percent,
                      bar,
                      index,
                      ) {
                    return FlDotCirclePainter(
                      radius: 3.5,
                      color:
                      _cyan,
                      strokeWidth:
                      2,
                      strokeColor:
                      _surface,
                    );
                  },
                ),
                belowBarData:
                BarAreaData(
                  show: true,
                  color: _cyan
                      .withOpacity(
                    0.07,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderChart(
      Map<String, dynamic> data,
      ) {
    final male =
    data['male'] as int;

    final female =
    data['female'] as int;

    final other =
    data['other'] as int;

    final total =
        male + female + other;

    return _chartCard(
      title: "Patient demographics",
      subtitle:
      "Gender distribution across registered patients",
      icon: Icons
          .pie_chart_outline_rounded,
      child: SizedBox(
        height: 265,
        child: total == 0
            ? _chartEmpty(
          "No demographic data yet",
        )
            : Row(
          children: [
            Expanded(
              flex: 6,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius:
                  52,
                  sectionsSpace: 3,
                  sections: [
                    PieChartSectionData(
                      value:
                      male.toDouble(),
                      title:
                      _percentage(
                        male,
                        total,
                      ),
                      radius: 54,
                      color:
                      _cyan,
                      titleStyle:
                      GoogleFonts
                          .inter(
                        color:
                        Colors.white,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),
                    PieChartSectionData(
                      value:
                      female.toDouble(),
                      title:
                      _percentage(
                        female,
                        total,
                      ),
                      radius: 54,
                      color:
                      _purple,
                      titleStyle:
                      GoogleFonts
                          .inter(
                        color:
                        Colors.white,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),
                    PieChartSectionData(
                      value:
                      other.toDouble(),
                      title:
                      _percentage(
                        other,
                        total,
                      ),
                      radius: 54,
                      color:
                      _teal,
                      titleStyle:
                      GoogleFonts
                          .inter(
                        color:
                        Colors.white,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  _legendItem(
                    "Male",
                    male,
                    _cyan,
                  ),
                  const SizedBox(
                      height: 13),
                  _legendItem(
                    "Female",
                    female,
                    _purple,
                  ),
                  const SizedBox(
                      height: 13),
                  _legendItem(
                    "Other",
                    other,
                    _teal,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _percentage(
      int value,
      int total,
      ) {
    if (total == 0) {
      return "0%";
    }

    return "${((value / total) * 100).round()}%";
  }

  Widget _legendItem(
      String title,
      int value,
      Color color,
      ) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
          BoxDecoration(
            color: color,
            shape:
            BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style:
            GoogleFonts.inter(
              color:
              _secondaryText,
              fontSize: 9.5,
              fontWeight:
              FontWeight.w500,
            ),
          ),
        ),
        Text(
          value.toString(),
          style:
          GoogleFonts.inter(
            color: _white,
            fontSize: 10,
            fontWeight:
            FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyBarChart(
      Map<String, dynamic> data,
      ) {
    final Map<int, int>
    monthly =
    data['monthlyPatients']
    as Map<int, int>;

    final now = DateTime.now();

    double maxY = 0;

    final List<BarChartGroupData>
    groups = [];

    for (int i = 5; i >= 0; i--) {
      final date =
      DateTime(
        now.year,
        now.month - i,
      );

      final key =
          date.year * 12 +
              date.month;

      final count =
          monthly[key] ?? 0;

      maxY = math.max(
        maxY,
        count.toDouble(),
      );

      groups.add(
        BarChartGroupData(
          x: 5 - i,
          barRods: [
            BarChartRodData(
              toY:
              count.toDouble(),
              width: 18,
              borderRadius:
              BorderRadius.circular(
                5,
              ),
              color: _teal,
            ),
          ],
        ),
      );
    }

    if (maxY < 5) {
      maxY = 5;
    }

    return _chartCard(
      title: "Monthly registrations",
      subtitle:
      "Patient volume by month",
      icon: Icons
          .bar_chart_rounded,
      child: SizedBox(
        height: 265,
        child: BarChart(
          BarChartData(
            maxY: maxY + 1,
            minY: 0,
            gridData:
            FlGridData(
              show: true,
              drawVerticalLine:
              false,
              horizontalInterval:
              maxY <= 5
                  ? 1
                  : maxY / 4,
              getDrawingHorizontalLine:
                  (value) =>
                  FlLine(
                    color: Colors.white
                        .withOpacity(
                      0.05,
                    ),
                    strokeWidth: 1,
                  ),
            ),
            borderData:
            FlBorderData(
              show: false,
            ),
            barGroups: groups,
            titlesData:
            FlTitlesData(
              topTitles:
              const AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  false,
                ),
              ),
              rightTitles:
              const AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  false,
                ),
              ),
              leftTitles:
              AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles: true,
                  reservedSize:
                  30,
                  getTitlesWidget:
                      (value, meta) =>
                      Text(
                        value.round()
                            .toString(),
                        style:
                        GoogleFonts
                            .inter(
                          color:
                          _mutedText,
                          fontSize:
                          8,
                        ),
                      ),
                ),
              ),
              bottomTitles:
              AxisTitles(
                sideTitles:
                SideTitles(
                  showTitles:
                  true,
                  reservedSize:
                  30,
                  getTitlesWidget:
                      (value, meta) {
                    final index =
                    value.round();

                    if (index <
                        0 ||
                        index >
                            5) {
                      return const SizedBox
                          .shrink();
                    }

                    final date =
                    DateTime(
                      now.year,
                      now.month -
                          (5 -
                              index),
                    );

                    const months = [
                      'Jan',
                      'Feb',
                      'Mar',
                      'Apr',
                      'May',
                      'Jun',
                      'Jul',
                      'Aug',
                      'Sep',
                      'Oct',
                      'Nov',
                      'Dec',
                    ];

                    return Padding(
                      padding:
                      const EdgeInsets
                          .only(
                        top: 8,
                      ),
                      child: Text(
                        months[
                        date.month -
                            1],
                        style:
                        GoogleFonts
                            .inter(
                          color:
                          _mutedText,
                          fontSize:
                          8.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData:
            BarTouchData(
              enabled: true,
              touchTooltipData:
              BarTouchTooltipData(
                getTooltipItem:
                    (
                    group,
                    groupIndex,
                    rod,
                    rodIndex,
                    ) {
                  return BarTooltipItem(
                    "${rod.toY.round()} patients",
                    GoogleFonts
                        .inter(
                      color:
                      Colors.white,
                      fontSize: 10,
                      fontWeight:
                      FontWeight
                          .w700,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorWorkload(
      Map<String, dynamic> data,
      ) {
    final Map<String, int>
    assignments =
    Map<String, int>.from(
      data['doctorAssignments']
      as Map,
    );

    final doctors =
    data['doctors']
    as List<QueryDocumentSnapshot>;

    final List<
        Map<String, dynamic>>
    workload = [];

    for (final doctor
    in doctors) {
      final doctorData =
      doctor.data()
      as Map<String,
          dynamic>;

      final name =
          doctorData['name']
              ?.toString() ??
              "Doctor";

      workload.add(
        {
          'name': name,
          'count':
          assignments[
          doctor.id] ??
              0,
        },
      );
    }

    workload.sort(
          (a, b) =>
          (b['count'] as int)
              .compareTo(
            a['count'] as int,
          ),
    );

    final display =
    workload.take(5).toList();

    return _chartCard(
      title: "Surgeon workload",
      subtitle:
      "Patients assigned per surgeon",
      icon: Icons
          .medical_services_outlined,
      child: SizedBox(
        height: 265,
        child: display.isEmpty
            ? _chartEmpty(
          "No surgeon assignment data",
        )
            : ListView.separated(
          physics:
          const NeverScrollableScrollPhysics(),
          itemCount:
          display.length,
          separatorBuilder:
              (_, __) =>
          const SizedBox(
            height: 12,
          ),
          itemBuilder:
              (context, index) {
            final item =
            display[index];

            final name =
            item['name']
                .toString();

            final count =
            item['count']
            as int;

            final maxCount =
            display
                .map(
                  (e) =>
              e['count']
              as int,
            )
                .fold<int>(
              0,
              math.max,
            );

            final ratio =
            maxCount == 0
                ? 0.0
                : count /
                maxCount;

            return Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines:
                        1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                        style:
                        GoogleFonts
                            .inter(
                          color:
                          _secondaryText,
                          fontSize:
                          9.5,
                          fontWeight:
                          FontWeight.bold
                        ),
                      ),
                    ),
                    Text(
                      count
                          .toString(),
                      style:
                      GoogleFonts
                          .inter(
                        color:
                        _white,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight
                        .bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                    height: 6),
                ClipRRect(
                  borderRadius:
                  BorderRadius
                      .circular(
                    10,
                  ),
                  child:
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor:
                    Colors.white
                        .withOpacity(
                      0.05,
                    ),
                    color:
                    _cyan,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnalyticsInsight(
      Map<String, dynamic> data,
      ) {
    final total =
    data['totalPatients']
    as int;

    final documents =
    data['totalDocuments']
    as int;

    final doctors =
    data['totalDoctors']
    as int;

    String insight;

    if (total == 0) {
      insight =
      "Your clinical registry is ready for its first patient record.";
    } else if (doctors == 0) {
      insight =
      "Patient records are present, but no surgeons are currently registered for assignment.";
    } else if (documents == 0) {
      insight =
      "$total patient records are registered. Diagnostic documents have not yet been uploaded.";
    } else {
      insight =
      "$total patient records and $documents diagnostic documents are currently available across $doctors registered surgeons.";
    }

    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(
        17,
      ),
      decoration:
      BoxDecoration(
        gradient:
        LinearGradient(
          colors: [
            _teal.withOpacity(
              0.10,
            ),
            _cyan.withOpacity(
              0.035,
            ),
          ],
        ),
        borderRadius:
        BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color: _cyan
              .withOpacity(0.09),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            width: 39,
            height: 39,
            decoration:
            BoxDecoration(
              color: _cyan
                  .withOpacity(
                0.08,
              ),
              borderRadius:
              BorderRadius.circular(
                12,
              ),
            ),
            child: const Icon(
              Icons
                  .insights_outlined,
              color: _cyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  "Operational insight",
                  style:
                  GoogleFonts.inter(
                    color: _white,
                    fontSize: 11,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight,
                  style:
                  GoogleFonts.inter(
                    color:
                    _secondaryText,
                    fontSize: 10,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return _glassCard(
      padding:
      const EdgeInsets.fromLTRB(
        18,
        17,
        18,
        12,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(
                icon,
                color: _cyan,
                size: 37,
              ),
              const SizedBox(width: 11),
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
                        color: _white,
                        fontSize: 12,
                        fontWeight:
                        FontWeight
                            .w700,
                      ),
                    ),
                    const SizedBox(
                        height: 3),
                    Text(
                      subtitle,
                      style:
                      GoogleFonts.inter(
                        color:
                        _mutedText,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _chartEmpty(
      String message,
      ) {
    return Center(
      child: Text(
        message,
        style:
        GoogleFonts.inter(
          color: _mutedText,
          fontSize: 10,
        ),
      ),
    );
  }

  // ===========================================================================
  // SETTINGS
  // ===========================================================================

  Widget _buildSettings() {
    final user =
        FirebaseAuth.instance
            .currentUser;

    if (user == null) {
      return _buildErrorState(
        "No authenticated administrator found.",
      );
    }

    final userDoc =
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    return StreamBuilder<
        DocumentSnapshot>(
      stream: userDoc.snapshots(),
      builder: (
          context,
          snapshot,
          ) {
        if (!snapshot.hasData) {
          return _buildLoadingState();
        }

        final data =
            snapshot.data!.data()
            as Map<String,
                dynamic>? ??
                {};

        final name =
            data['name']
                ?.toString() ??
                user.displayName ??
                'Administrator';

        final email =
            data['email']
                ?.toString() ??
                user.email ??
                'N/A';

        final photoUrl =
            data['photoUrl']
                ?.toString() ??
                user.photoURL;

        return _buildScrollablePage(
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 800,
              ),
              child: Padding(
                padding:
                const EdgeInsets
                    .all(
                  22,
                ),
                child: Column(
                  children: [
                    _sectionEyebrow(
                      "ACCOUNT & SECURITY",
                    ),
                    const SizedBox(
                        height: 8),
                    Text(
                      "Administrator profile",
                      style:
                      GoogleFonts.poppins(
                        color: _white,
                        fontSize: 27,
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),
                    const SizedBox(
                        height: 20),
                    _buildProfileCard(
                      name,
                      email,
                      photoUrl,
                      userDoc,
                    ),
                    const SizedBox(
                        height: 14),
                    _buildSettingsAction(
                      icon: Icons
                          .lock_reset_rounded,
                      title:
                      "Change password",
                      subtitle:
                      "Update your Firebase authentication password",
                      color: _warning,
                      onTap: () {
                        _showChangePasswordDialog(
                          context,
                        );
                      },
                    ),
                    const SizedBox(
                        height: 10),
                    _buildSettingsAction(
                      icon: Icons
                          .logout_rounded,
                      title:
                      "Sign out",
                      subtitle:
                      "End the current administrator session",
                      color: _danger,
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(
      String name,
      String email,
      String? photoUrl,
      DocumentReference userDoc,
      ) {
    return _glassCard(
      padding:
      const EdgeInsets.all(
        22,
      ),
      child: Column(
        children: [
          Container(
            width: 94,
            height: 94,
            decoration:
            BoxDecoration(
              shape:
              BoxShape.circle,
              gradient:
              const LinearGradient(
                colors: [
                  _teal,
                  _cyan,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _cyan
                      .withOpacity(
                    0.18,
                  ),
                  blurRadius: 30,
                ),
              ],
            ),
            padding:
            const EdgeInsets.all(
              3,
            ),
            child: CircleAvatar(
              backgroundColor:
              _surface,
              backgroundImage:
              photoUrl != null &&
                  photoUrl
                      .isNotEmpty
                  ? NetworkImage(
                photoUrl,
              )
                  : null,
              child: photoUrl == null ||
                  photoUrl.isEmpty
                  ? const Icon(
                Icons.person,
                color:
                _secondaryText,
                size: 39,
              )
                  : null,
            ),
          ),
          const SizedBox(
              height: 15),
          Text(
            name,
            textAlign:
            TextAlign.center,
            style:
            GoogleFonts.poppins(
              color: _white,
              fontSize: 20,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style:
            GoogleFonts.inter(
              color:
              _secondaryText,
              fontSize: 11,
            ),
          ),
          const SizedBox(
              height: 12),
          Container(
            padding:
            const EdgeInsets
                .symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration:
            BoxDecoration(
              color: _success
                  .withOpacity(
                0.06,
              ),
              borderRadius:
              BorderRadius.circular(
                9,
              ),
              border: Border.all(
                color: _success
                    .withOpacity(
                  0.10,
                ),
              ),
            ),
            child: Text(
              "ADMINISTRATOR",
              style:
              GoogleFonts.inter(
                color:
                _success,
                fontSize: 8.5,
                fontWeight:
                FontWeight.w800,
                letterSpacing:
                1.1,
              ),
            ),
          ),
          const SizedBox(
              height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child:
            OutlinedButton.icon(
              onPressed: () {
                _showEditProfileDialog(
                  context,
                  userDoc,
                  name,
                  photoUrl ?? '',
                );
              },
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                _cyan,
                side: BorderSide(
                  color: _cyan
                      .withOpacity(
                    0.18,
                  ),
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    13,
                  ),
                ),
              ),
              icon: const Icon(
                Icons
                    .edit_outlined,
                size: 17,
              ),
              label: Text(
                "Edit profile",
                style:
                GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight:
                  FontWeight
                      .w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius:
      BorderRadius.circular(
        16,
      ),
      onTap: onTap,
      child: Container(
        padding:
        const EdgeInsets.all(
          15,
        ),
        decoration:
        BoxDecoration(
          color: Colors.white
              .withOpacity(0.032),
          borderRadius:
          BorderRadius.circular(
            16,
          ),
          border: Border.all(
            color: Colors.white
                .withOpacity(0.055),
          ),
        ),
        child: Row(
          children: [
            _iconBox(
              icon,
              color: color,
            ),
            const SizedBox(width: 12),
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
                      color: _white,
                      fontSize: 11.5,
                      fontWeight:
                      FontWeight
                          .w700,
                    ),
                  ),
                  const SizedBox(
                      height: 3),
                  Text(
                    subtitle,
                    style:
                    GoogleFonts.inter(
                      color:
                      _mutedText,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons
                  .arrow_forward_ios_rounded,
              color: _mutedText,
              size: 13,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // EDIT PROFILE
  // ===========================================================================

  void _showEditProfileDialog(
      BuildContext context,
      DocumentReference userDoc,
      String currentName,
      String currentPhotoUrl,
      ) {
    final nameController =
    TextEditingController(
      text: currentName,
    );

    final photoController =
    TextEditingController(
      text: currentPhotoUrl,
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _buildProfessionalDialog(
          title: "Edit Profile",
          icon: Icons
              .manage_accounts_outlined,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(
                nameController,
                "Full Name",
                Icons.person_outline,
              ),
              const SizedBox(height: 14),
              _dialogField(
                photoController,
                "Profile Photo URL",
                Icons
                    .image_outlined,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    dialogContext,
                  ),
              child: Text(
                "Cancel",
                style:
                GoogleFonts.inter(
                  color:
                  _mutedText,
                ),
              ),
            ),
            FilledButton(
              style:
              FilledButton.styleFrom(
                backgroundColor:
                _teal,
              ),
              onPressed: () async {
                final name =
                nameController
                    .text
                    .trim();

                final photo =
                photoController
                    .text
                    .trim();

                if (name.isEmpty) {
                  _showSnack(
                    "Name cannot be empty.",
                  );
                  return;
                }

                try {
                  await userDoc.update(
                    {
                      'name': name,
                      'photoUrl':
                      photo,
                    },
                  );

                  final user =
                      FirebaseAuth
                          .instance
                          .currentUser;

                  await user?.updateDisplayName(
                    name,
                  );

                  if (photo.isNotEmpty) {
                    await user
                        ?.updatePhotoURL(
                      photo,
                    );
                  }

                  if (!mounted) return;

                  Navigator.pop(
                    dialogContext,
                  );

                  _showSnack(
                    "Profile updated successfully.",
                    success: true,
                  );
                } catch (e) {
                  _showSnack(
                    "Error updating profile: $e",
                  );
                }
              },
              child: Text(
                "Save changes",
                style:
                GoogleFonts.inter(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // CHANGE PASSWORD
  // ===========================================================================

  void _showChangePasswordDialog(
      BuildContext context,
      ) {
    final passwordController =
    TextEditingController();

    final confirmController =
    TextEditingController();

    bool obscurePassword = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            return _buildProfessionalDialog(
              title:
              "Change Password",
              icon: Icons
                  .lock_reset_rounded,
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  _dialogPasswordField(
                    controller:
                    passwordController,
                    label:
                    "New Password",
                    obscure:
                    obscurePassword,
                    onToggle: () {
                      setDialogState(
                            () {
                          obscurePassword =
                          !obscurePassword;
                        },
                      );
                    },
                  ),
                  const SizedBox(
                      height: 14),
                  _dialogPasswordField(
                    controller:
                    confirmController,
                    label:
                    "Confirm Password",
                    obscure:
                    obscureConfirm,
                    onToggle: () {
                      setDialogState(
                            () {
                          obscureConfirm =
                          !obscureConfirm;
                        },
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                        dialogContext,
                      ),
                  child: Text(
                    "Cancel",
                    style:
                    GoogleFonts.inter(
                      color:
                      _mutedText,
                    ),
                  ),
                ),
                FilledButton(
                  style:
                  FilledButton.styleFrom(
                    backgroundColor:
                    _teal,
                  ),
                  onPressed:
                      () async {
                    final password =
                    passwordController
                        .text
                        .trim();

                    final confirm =
                    confirmController
                        .text
                        .trim();

                    if (password.length <
                        6) {
                      _showSnack(
                        "Password must contain at least 6 characters.",
                      );
                      return;
                    }

                    if (password !=
                        confirm) {
                      _showSnack(
                        "Passwords do not match.",
                      );
                      return;
                    }

                    try {
                      await FirebaseAuth
                          .instance
                          .currentUser!
                          .updatePassword(
                        password,
                      );

                      if (!mounted)
                        return;

                      Navigator.pop(
                        dialogContext,
                      );

                      _showSnack(
                        "Password updated successfully.",
                        success:
                        true,
                      );
                    } on FirebaseAuthException catch (e) {
                      _showSnack(
                        e.message ??
                            "Unable to update password.",
                      );
                    } catch (e) {
                      _showSnack(
                        "Error updating password: $e",
                      );
                    }
                  },
                  child: Text(
                    "Update password",
                    style:
                    GoogleFonts.inter(
                      fontWeight:
                      FontWeight
                          .w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================

  Widget _buildPageHeader({
    required String eyebrow,
    required String title,
    required String description,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment
                .start,
            children: [
              _sectionEyebrow(
                eyebrow,
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style:
                GoogleFonts.poppins(
                  color: _white,
                  fontSize: 27,
                  fontWeight:
                  FontWeight.w800,
                  letterSpacing:
                  -0.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style:
                GoogleFonts.inter(
                  color:
                  _secondaryText,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Padding(
            padding:
            const EdgeInsets.only(
              left: 12,
              top: 8,
            ),
            child: trailing,
          ),
      ],
    );
  }

  Widget _sectionEyebrow(
      String text,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 2,
          decoration:
          BoxDecoration(
            color: _cyan,
            borderRadius:
            BorderRadius.circular(
              4,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style:
          GoogleFonts.inter(
            color: _cyan,
            fontSize: 8.5,
            fontWeight:
            FontWeight.w800,
            letterSpacing:
            1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration:
      BoxDecoration(
        color: _success
            .withOpacity(0.055),
        borderRadius:
        BorderRadius.circular(
          9,
        ),
        border: Border.all(
          color: _success
              .withOpacity(0.10),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
            const BoxDecoration(
              color: _success,
              shape:
              BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            "LIVE",
            style:
            GoogleFonts.inter(
              color: _success,
              fontSize: 8,
              fontWeight:
              FontWeight.w800,
              letterSpacing:
              1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(
      int count,
      String label,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration:
      BoxDecoration(
        color: _cyan
            .withOpacity(0.045),
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color: _cyan
              .withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style:
            GoogleFonts.poppins(
              color: _white,
              fontSize: 15,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style:
            GoogleFonts.inter(
              color: _mutedText,
              fontSize: 7.5,
              fontWeight:
              FontWeight.w800,
              letterSpacing:
              0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required String hint,
    required TextEditingController
    controller,
  }) {
    return TextField(
      controller: controller,
      style:
      GoogleFonts.inter(
        color: _white,
        fontSize: 11,
      ),
      cursorColor: _cyan,
      decoration:
      InputDecoration(
        hintText: hint,
        hintStyle:
        GoogleFonts.inter(
          color: _mutedText,
          fontSize: 10.5,
        ),
        prefixIcon:
        const Icon(
          Icons.search_rounded,
          color: _mutedText,
          size: 19,
        ),
        suffixIcon:
        controller.text.isNotEmpty
            ? IconButton(
          onPressed: () {
            controller.clear();
          },
          icon:
          const Icon(
            Icons
                .close_rounded,
            color:
            _mutedText,
            size: 17,
          ),
        )
            : null,
        filled: true,
        fillColor:
        Colors.white.withOpacity(
          0.03,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          BorderSide(
            color: Colors.white
                .withOpacity(
              0.055,
            ),
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          const BorderSide(
            color: _cyan,
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController
    controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style:
      GoogleFonts.inter(
        color: _white,
        fontSize: 11,
        fontWeight:
        FontWeight.w500,
      ),
      cursorColor: _cyan,
      decoration:
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
        GoogleFonts.inter(
          color: _secondaryText,
          fontSize: 10.5,
        ),
        hintStyle:
        GoogleFonts.inter(
          color: _mutedText,
          fontSize: 9.5,
        ),
        prefixIcon:
        Icon(
          icon,
          color: _mutedText,
          size: 18,
        ),
        filled: true,
        fillColor:
        Colors.white.withOpacity(
          0.03,
        ),
        contentPadding:
        const EdgeInsets
            .symmetric(
          horizontal: 14,
          vertical: 17,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          BorderSide(
            color: Colors.white
                .withOpacity(
              0.06,
            ),
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          const BorderSide(
            color: _cyan,
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<
        DropdownMenuItem<String>>
    items,
    required ValueChanged<String?>
    onChanged,
  }) {
    return DropdownButtonFormField<
        String>(
      value: value,
      dropdownColor:
      const Color(0xFF102A3D),
      style:
      GoogleFonts.inter(
        color: _white,
        fontSize: 10.5,
      ),
      iconEnabledColor:
      _mutedText,
      decoration:
      InputDecoration(
        labelText: label,
        labelStyle:
        GoogleFonts.inter(
          color: _secondaryText,
          fontSize: 10.5,
        ),
        prefixIcon:
        Icon(
          icon,
          color: _mutedText,
          size: 18,
        ),
        filled: true,
        fillColor:
        Colors.white.withOpacity(
          0.03,
        ),
        contentPadding:
        const EdgeInsets
            .symmetric(
          horizontal: 12,
          vertical: 5,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          BorderSide(
            color: Colors.white
                .withOpacity(
              0.06,
            ),
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          borderSide:
          const BorderSide(
            color: _cyan,
            width: 1,
          ),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding =
    const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration:
      BoxDecoration(
        color:
        _surface.withOpacity(
          0.88,
        ),
        borderRadius:
        BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.18),
            blurRadius: 35,
            offset:
            const Offset(0, 15),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconBox(
      IconData icon, {
        Color color = _cyan,
        double size = 42,
      }) {
    return Container(
      width: size,
      height: size,
      decoration:
      BoxDecoration(
        color: color.withOpacity(
          0.075,
        ),
        borderRadius:
        BorderRadius.circular(
          12,
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: size * 0.46,
      ),
    );
  }

  Widget _buildScrollablePage({
    required Widget child,
  }) {
    return SingleChildScrollView(
      physics:
      const BouncingScrollPhysics(),
      padding:
      const EdgeInsets.only(
        bottom: 35,
      ),
      child: child,
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 27,
            height: 27,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
              color: _cyan,
            ),
          ),
          const SizedBox(
              height: 13),
          Text(
            "Loading clinical data...",
            style:
            GoogleFonts.inter(
              color:
              _mutedText,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
      String message,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(
          30,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            const Icon(
              Icons
                  .error_outline_rounded,
              color: _danger,
              size: 42,
            ),
            const SizedBox(
                height: 12),
            Text(
              message,
              textAlign:
              TextAlign.center,
              style:
              GoogleFonts.inter(
                color:
                _secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 45,
      ),
      decoration:
      BoxDecoration(
        color: Colors.white
            .withOpacity(0.025),
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: _mutedText,
            size: 42,
          ),
          const SizedBox(height: 13),
          Text(
            title,
            style:
            GoogleFonts.inter(
              color: _white,
              fontSize: 12,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            textAlign:
            TextAlign.center,
            style:
            GoogleFonts.inter(
              color:
              _mutedText,
              fontSize: 9.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DIALOG HELPERS
  // ===========================================================================

  Widget _buildProfessionalDialog({
    required String title,
    required IconData icon,
    required Widget child,
    required List<Widget> actions,
  }) {
    return AlertDialog(
      backgroundColor:
      const Color(0xFF102A3D),
      surfaceTintColor:
      Colors.transparent,
      shape:
      RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(
          22,
        ),
        side: BorderSide(
          color: Colors.white
              .withOpacity(0.07),
        ),
      ),
      titlePadding:
      const EdgeInsets.fromLTRB(
        22,
        20,
        22,
        8,
      ),
      contentPadding:
      const EdgeInsets.fromLTRB(
        22,
        10,
        22,
        10,
      ),
      actionsPadding:
      const EdgeInsets.fromLTRB(
        15,
        5,
        15,
        15,
      ),
      title: Row(
        children: [
          _iconBox(
            icon,
            size: 40,
          ),
          const SizedBox(width: 11),
          Text(
            title,
            style:
            GoogleFonts.poppins(
              color: _white,
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
      content: child,
      actions: actions,
    );
  }

  Widget _dialogField(
      TextEditingController controller,
      String label,
      IconData icon, {
        TextInputType? keyboardType,
      }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style:
      GoogleFonts.inter(
        color: _white,
        fontSize: 11,
      ),
      cursorColor: _cyan,
      decoration:
      InputDecoration(
        labelText: label,
        labelStyle:
        GoogleFonts.inter(
          color: _secondaryText,
          fontSize: 10,
        ),
        prefixIcon:
        Icon(
          icon,
          color: _mutedText,
          size: 18,
        ),
        filled: true,
        fillColor:
        Colors.white.withOpacity(
          0.035,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            13,
          ),
          borderSide:
          BorderSide(
            color: Colors.white
                .withOpacity(
              0.06,
            ),
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            13,
          ),
          borderSide:
          const BorderSide(
            color: _cyan,
          ),
        ),
      ),
    );
  }

  Widget _dialogPasswordField({
    required TextEditingController
    controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style:
      GoogleFonts.inter(
        color: _white,
        fontSize: 11,
      ),
      decoration:
      InputDecoration(
        labelText: label,
        labelStyle:
        GoogleFonts.inter(
          color: _secondaryText,
          fontSize: 10,
        ),
        prefixIcon:
        const Icon(
          Icons.lock_outline_rounded,
          color: _mutedText,
          size: 18,
        ),
        suffixIcon:
        IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure
                ? Icons
                .visibility_outlined
                : Icons
                .visibility_off_outlined,
            color: _mutedText,
            size: 18,
          ),
        ),
        filled: true,
        fillColor:
        Colors.white.withOpacity(
          0.035,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            13,
          ),
          borderSide:
          BorderSide(
            color: Colors.white
                .withOpacity(
              0.06,
            ),
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(
            13,
          ),
          borderSide:
          const BorderSide(
            color: _cyan,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CONFIRMATION
  // ===========================================================================

  Future<bool> _showDeleteConfirmation({
    required String title,
    required String message,
  }) async {
    final result =
    await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor:
          const Color(0xFF102A3D),
          surfaceTintColor:
          Colors.transparent,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              20,
            ),
          ),
          title: Text(
            title,
            style:
            GoogleFonts.poppins(
              color: _white,
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style:
            GoogleFonts.inter(
              color:
              _secondaryText,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    false,
                  ),
              child: Text(
                "Cancel",
                style:
                GoogleFonts.inter(
                  color:
                  _mutedText,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              style:
              FilledButton.styleFrom(
                backgroundColor:
                _danger,
              ),
              onPressed: () =>
                  Navigator.pop(
                    context,
                    true,
                  ),
              child: Text(
                "Delete",
                style:
                GoogleFonts.inter(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // ===========================================================================
  // SNACKBAR
  // ===========================================================================

  void _showSnack(
      String message, {
        bool success = false,
        Duration duration =
        const Duration(seconds: 3),
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior:
          SnackBarBehavior.floating,
          margin:
          const EdgeInsets.all(
            16,
          ),
          backgroundColor:
          const Color(0xFF172B3A),
          elevation: 10,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              13,
            ),
          ),
          content: Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration:
                BoxDecoration(
                  color:
                  (success
                      ? _success
                      : _danger)
                      .withOpacity(
                    0.08,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    9,
                  ),
                ),
                child: Icon(
                  success
                      ? Icons
                      .check_rounded
                      : Icons
                      .error_outline_rounded,
                  color: success
                      ? _success
                      : _danger,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style:
                  GoogleFonts.inter(
                    color: _white,
                    fontSize: 10.5,
                    fontWeight:
                    FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _tabController.dispose();

    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _emailController.dispose();

    _patientSearchController.dispose();

    _pageController.dispose();
    _backgroundController.dispose();
    _pulseController.dispose();

    if (_modelLoaded) {
      _interpreter.close();
    }

    super.dispose();
  }
}

// =============================================================================
// MEDICAL GRID
// =============================================================================

class _MedicalGridPainter
    extends CustomPainter {
  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    final paint = Paint()
      ..color = Colors.white
          .withOpacity(0.014)
      ..strokeWidth = 0.7;

    const spacing = 44.0;

    for (
    double x = 0;
    x <= size.width;
    x += spacing
    ) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (
    double y = 0;
    y <= size.height;
    y += spacing
    ) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate,
      ) {
    return false;
  }
}