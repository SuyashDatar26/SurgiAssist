
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'admin/admin_dashboard.dart';
import 'surgeon/surgeon_dashboard.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
// ===========================================================================
// COLORS
// ===========================================================================

  static const Color _background = Color(0xFF06131F);
  static const Color _backgroundMid = Color(0xFF0B1F33);
  static const Color _surface = Color(0xFF102A3D);
  static const Color _surfaceLight = Color(0xFF15384D);

  static const Color _teal = Color(0xFF0E7490);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _cyanLight = Color(0xFF67E8F9);

  static const Color _white = Color(0xFFF8FAFC);
  static const Color _secondaryText = Color(0xFF9DB2C1);
  static const Color _mutedText = Color(0xFF6F8796);

  static const Color _success = Color(0xFF34D399);
  static const Color _warning = Color(0xFFFBBF24);
  static const Color _danger = Color(0xFFFB7185);

// ===========================================================================
// FORM
// ===========================================================================

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController =
  TextEditingController();

  final TextEditingController _phoneController =
  TextEditingController();

  final TextEditingController _hospitalController =
  TextEditingController();

  final TextEditingController _specializationController =
  TextEditingController();

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _passwordController =
  TextEditingController();

  final TextEditingController _confirmPasswordController =
  TextEditingController();

// ===========================================================================
// FOCUS
// ===========================================================================

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _hospitalFocus = FocusNode();
  final FocusNode _specializationFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

// ===========================================================================
// STATE
// ===========================================================================

  String _selectedRole = 'surgeon';

  bool _isLoading = false;
  bool _isGoogleLoading = false;

  bool _obscurePass = true;
  bool _obscureConfirmPass = true;

  bool _googleInitialized = false;

  String? _errorMessage;

// ===========================================================================
// GOOGLE
// ===========================================================================

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

// ===========================================================================
// ANIMATIONS
// ===========================================================================

  late AnimationController _pageController;
  late AnimationController _orbController;
  late AnimationController _pulseController;

  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;
  late Animation<double> _orbAnimation;
  late Animation<double> _pulseAnimation;

// ===========================================================================
// INIT
// ===========================================================================

  @override
  void initState() {
    super.initState();

    _setupAnimations();
    _setupFocusListeners();
    _setupPasswordListener();
    _initializeGoogleSignIn();

    _pageController.forward();
    _orbController.repeat();
    _pulseController.repeat(reverse: true);
  }

  void _setupAnimations() {
    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
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
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageController,
        curve: Curves.easeOutCubic,
      ),
    );

    _orbAnimation = CurvedAnimation(
      parent: _orbController,
      curve: Curves.linear,
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
  }

  void _setupFocusListeners() {
    _nameFocus.addListener(_refresh);
    _phoneFocus.addListener(_refresh);
    _hospitalFocus.addListener(_refresh);
    _specializationFocus.addListener(_refresh);
    _emailFocus.addListener(_refresh);
    _passwordFocus.addListener(_refresh);
    _confirmPasswordFocus.addListener(_refresh);
  }

  void _setupPasswordListener() {
    _passwordController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

// ===========================================================================
// GOOGLE INITIALIZATION
// ===========================================================================

  Future<void> _initializeGoogleSignIn() async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        return;
      }

      await _googleSignIn.initialize();

      if (!mounted) return;

      setState(() {
        _googleInitialized = true;
      });
    } catch (e) {
      debugPrint(
        'Google Sign-In initialization error: $e',
      );
    }
  }

// ===========================================================================
// NORMAL REGISTRATION
// ===========================================================================

  Future<void> _registerUser() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isLoading || _isGoogleLoading) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    UserCredential? userCredential;

    try {
      userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Unable to create your account.',
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': email,
        'hospital': _hospitalController.text.trim(),
        'specialization':
        _selectedRole == 'surgeon'
            ? _specializationController.text.trim()
            : '',
        'role': _selectedRole,
        'createdAt': Timestamp.now(),
        'authProvider': 'email',
      });

      if (!mounted) return;

      _showSuccess(
        'Registration successful! Redirecting...',
      );

      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (!mounted) return;

      await _routeByRole(_selectedRole);
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } catch (e) {
      debugPrint(
        'REGISTRATION ERROR: $e',
      );

      _showError(
        'Something went wrong while creating your account.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

// ===========================================================================
// GOOGLE REGISTRATION
// ===========================================================================

  Future<void> _signUpWithGoogle() async {
    FocusScope.of(context).unfocus();

    if (_isLoading || _isGoogleLoading) {
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      _showError(
        'Google Sign-Up is unavailable on Windows. '
            'Please use email and password.',
      );
      return;
    }

    if (!_googleInitialized) {
      _showError(
        'Google Sign-In is still initializing. Please try again.',
      );

      await _initializeGoogleSignIn();

      if (!_googleInitialized) {
        return;
      }
    }

    HapticFeedback.lightImpact();

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      if (!_googleSignIn.supportsAuthenticate()) {
        _showError(
          'Google Sign-In is not available on this platform.',
        );
        return;
      }

      final GoogleSignInAccount googleUser =
      await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'google-user-null',
          message: 'Unable to retrieve your Google account.',
        );
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final existingUser = await userRef.get();

// -----------------------------------------------------------------------
// EXISTING GOOGLE ACCOUNT
// -----------------------------------------------------------------------

      if (existingUser.exists) {
        final existingData = existingUser.data();

        final existingRole =
        existingData?['role']
            ?.toString()
            .trim()
            .toLowerCase();

        if (existingRole == 'admin' ||
            existingRole == 'surgeon') {
          if (!mounted) return;

          _showSuccess(
            'Account already exists. Signing you in...',
          );

          await Future.delayed(
            const Duration(milliseconds: 450),
          );

          if (!mounted) return;

          await _routeByRole(existingRole!);
          return;
        }
      }

// -----------------------------------------------------------------------
// NEW GOOGLE ACCOUNT
// -----------------------------------------------------------------------

      final googleName =
          googleUser.displayName ??
              user.displayName ??
              '';

      final googleEmail =
      googleUser.email.isNotEmpty
          ? googleUser.email
          : user.email ?? '';

      await userRef.set({
        'uid': user.uid,
        'name': googleName,
        'phone': '',
        'email': googleEmail,
        'hospital': _hospitalController.text.trim(),
        'specialization':
        _selectedRole == 'surgeon'
            ? _specializationController.text.trim()
            : '',
        'role': _selectedRole,
        'createdAt': Timestamp.now(),
        'authProvider': 'google',
        'photoURL': user.photoURL,
      });

      if (!mounted) return;

      _showSuccess(
        'Google registration successful! Redirecting...',
      );

      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (!mounted) return;

      await _routeByRole(_selectedRole);
    } on GoogleSignInException catch (e) {
      debugPrint(
        'Google Sign-In error: ${e.code} - ${e.description}',
      );

      if (e.code !=
          GoogleSignInExceptionCode.canceled) {
        _showError(
          e.description ??
              'Google Sign-Up failed. Please try again.',
        );
      }
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } catch (e) {
      debugPrint(
        'GOOGLE REGISTRATION ERROR: $e',
      );

      _showError(
        'Google Sign-Up failed. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

// ===========================================================================
// ROLE ROUTING
// ===========================================================================

  Future<void> _routeByRole(String role) async {
    if (!mounted) return;

    if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (
              context,
              animation,
              secondaryAnimation,
              ) =>
              AdminDashboard(),
          transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
              ) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration:
          const Duration(milliseconds: 450),
        ),
      );
    } else if (role == 'surgeon') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (
              context,
              animation,
              secondaryAnimation,
              ) =>
              SurgeonDashboard(),
          transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
              ) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration:
          const Duration(milliseconds: 450),
        ),
      );
    }
  }

// ===========================================================================
// FIREBASE ERRORS
// ===========================================================================

  void _handleFirebaseError(
      FirebaseAuthException e,
      ) {
    String message;

    switch (e.code) {
      case 'invalid-email':
        message = 'Please enter a valid email address.';
        break;

      case 'email-already-in-use':
        message =
        'An account already exists with this email address.';
        break;

      case 'weak-password':
        message =
        'Your password is too weak. Use at least 6 characters.';
        break;

      case 'operation-not-allowed':
        message =
        'This registration method is currently disabled.';
        break;

      case 'network-request-failed':
        message =
        'Network connection failed. Please check your internet.';
        break;

      case 'credential-already-in-use':
        message =
        'This Google account is already associated with another account.';
        break;

      default:
        message =
            e.message ??
                'Registration failed. Please try again.';
    }

    _showError(message);
  }

// ===========================================================================
// VALIDATION
// ===========================================================================

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Enter your full name';
    }

    if (name.length < 2) {
      return 'Enter a valid name';
    }

    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) {
      return 'Enter phone number';
    }

    final digits =
    phone.replaceAll(RegExp(r'[^0-9+]'), '');

    if (digits.length < 10) {
      return 'Enter a valid phone number';
    }

    return null;
  }

  String? _validateHospital(String? value) {
    if ((value?.trim() ?? '').isEmpty) {
      return 'Enter hospital / organization';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Enter email address';
    }

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email)) {
      return 'Enter a valid email';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.length < 6) {
      return 'Minimum 6 characters';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }

    return null;
  }

// ===========================================================================
// PASSWORD STRENGTH
// ===========================================================================

  double _passwordStrength() {
    final password = _passwordController.text;

    if (password.isEmpty) {
      return 0;
    }

    double strength = 0;

    if (password.length >= 6) {
      strength += 0.25;
    }

    if (password.length >= 10) {
      strength += 0.15;
    }

    if (RegExp(r'[A-Z]').hasMatch(password)) {
      strength += 0.20;
    }

    if (RegExp(r'[0-9]').hasMatch(password)) {
      strength += 0.20;
    }

    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      strength += 0.20;
    }

    return strength.clamp(0, 1);
  }

  String _passwordStrengthText() {
    final strength = _passwordStrength();

    if (strength == 0) {
      return '';
    }

    if (strength < 0.45) {
      return 'Weak password';
    }

    if (strength < 0.75) {
      return 'Moderate password';
    }

    return 'Strong password';
  }

  Color _passwordStrengthColor() {
    final strength = _passwordStrength();

    if (strength < 0.45) {
      return _danger;
    }

    if (strength < 0.75) {
      return _warning;
    }

    return _success;
  }

// ===========================================================================
// SNACKBAR
// ===========================================================================

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          backgroundColor: const Color(0xFF172B3A),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: _danger,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _showSuccess(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(18),
          backgroundColor: const Color(0xFF172B3A),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _success.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: _success,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _pageFade,
              child: SlideTransition(
                position: _pageSlide,
                child: _buildResponsiveLayout(),
              ),
            ),
          ),
        ],
      ),
    );
  }

// ===========================================================================
// BACKGROUND
// ===========================================================================

  Widget _buildBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _orbAnimation,
        builder: (context, child) {
          final value = _orbAnimation.value;

          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
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
                left: -180 + (value * 55),
                top: -180,
                child: _buildAmbientOrb(
                  size: 420,
                  color: _teal,
                ),
              ),

              Positioned(
                right: -220 + (value * 65),
                bottom: -210,
                child: _buildAmbientOrb(
                  size: 460,
                  color: _cyan,
                ),
              ),

              Positioned(
                right: 100,
                top: 80 + (value * 30),
                child: _buildAmbientOrb(
                  size: 170,
                  color: _teal,
                ),
              ),

              Positioned.fill(
                child: CustomPaint(
                  painter: _MedicalGridPainter(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAmbientOrb({
    required double size,
    required Color color,
  }) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.15),
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
// RESPONSIVE
// ===========================================================================

  Widget _buildResponsiveLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          return _buildDesktopLayout();
        }

        if (constraints.maxWidth >= 700) {
          return _buildTabletLayout();
        }

        return _buildMobileLayout();
      },
    );
  }

// ===========================================================================
// DESKTOP
// ===========================================================================

  Widget _buildDesktopLayout() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 45,
          vertical: 30,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1220,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: _buildBrandPanel(),
              ),
              const SizedBox(width: 55),
              Expanded(
                flex: 6,
                child: _buildRegisterCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

// ===========================================================================
// TABLET
// ===========================================================================

  Widget _buildTabletLayout() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 35,
          vertical: 25,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 650,
          ),
          child: _buildRegisterCard(),
        ),
      ),
    );
  }

// ===========================================================================
// MOBILE
// ===========================================================================

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          28,
        ),
        child: _buildRegisterCard(
          mobile: true,
        ),
      ),
    );
  }

// ===========================================================================
// BRAND PANEL
// ===========================================================================

  Widget _buildBrandPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              alignment: Alignment.centerLeft,
              child: child,
            );
          },
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _teal,
                  _cyan,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _cyan.withOpacity(0.22),
                  blurRadius: 35,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),

        const SizedBox(height: 28),

        Text(
          'Join SurgiAssist',
          style: GoogleFonts.poppins(
            color: _white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),

        const SizedBox(height: 9),

        Text(
          'Create your secure clinical workspace\n'
              'and access intelligent surgical assistance.',
          style: GoogleFonts.poppins(
            color: _secondaryText,
            fontSize: 17,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 34),

        _buildFeature(
          icon: Icons.psychology_outlined,
          title: 'AI-Assisted Clinical Workflow',
          description:
          'Access intelligent procedure references and clinical information.',
        ),

        const SizedBox(height: 17),

        _buildFeature(
          icon: Icons.record_voice_over_outlined,
          title: 'Voice-Enabled Assistance',
          description:
          'Interact naturally with patient and procedure information.',
        ),

        const SizedBox(height: 17),

        _buildFeature(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Role-Based Access',
          description:
          'Dedicated administrative and surgeon workflows keep access controlled.',
        ),

        const SizedBox(height: 35),

        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'SECURE CLINICAL REGISTRATION',
              style: GoogleFonts.inter(
                color: _secondaryText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.35,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeature({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
          ),
          child: Icon(
            icon,
            color: _cyan,
            size: 21,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: _white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

// ===========================================================================
// REGISTER CARD
// ===========================================================================

  Widget _buildRegisterCard({
    bool mobile = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        mobile ? 20 : 28,
      ),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(
          mobile ? 23 : 27,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.075),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 45,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: _cyan.withOpacity(0.035),
            blurRadius: 55,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            if (mobile) ...[
              Center(
                child: _buildMobileLogo(),
              ),
              const SizedBox(height: 18),
            ],

            Text(
              'Create your account',
              style: GoogleFonts.poppins(
                color: _white,
                fontSize: mobile ? 24 : 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Enter your details to create your SurgiAssist profile.',
              style: GoogleFonts.inter(
                color: _secondaryText,
                fontSize: 12,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 23),

            _buildSectionLabel(
              icon: Icons.person_outline_rounded,
              title: 'PERSONAL INFORMATION',
            ),

            const SizedBox(height: 11),

            _buildTextField(
              controller: _nameController,
              focusNode: _nameFocus,
              label: 'Full Name',
              hint: 'Enter your full name',
              icon: Icons.person_outline_rounded,
              validator: _validateName,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  _phoneFocus.requestFocus(),
            ),

            const SizedBox(height: 12),

            _buildTextField(
              controller: _phoneController,
              focusNode: _phoneFocus,
              label: 'Phone Number',
              hint: 'Enter your phone number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: _validatePhone,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) =>
                  _hospitalFocus.requestFocus(),
            ),

            const SizedBox(height: 12),

            _buildTextField(
              controller: _hospitalController,
              focusNode: _hospitalFocus,
              label: 'Hospital / Organization',
              hint: 'Enter your hospital or organization',
              icon: Icons.local_hospital_outlined,
              validator: _validateHospital,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                if (_selectedRole == 'surgeon') {
                  _specializationFocus.requestFocus();
                } else {
                  _emailFocus.requestFocus();
                }
              },
            ),

            AnimatedSize(
              duration:
              const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: _selectedRole == 'surgeon'
                  ? Column(
                children: [
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller:
                    _specializationController,
                    focusNode:
                    _specializationFocus,
                    label: 'Specialization',
                    hint:
                    'e.g. Orthopaedics, General Surgery',
                    icon: Icons
                        .medical_information_outlined,
                    textInputAction:
                    TextInputAction.next,
                    onSubmitted: (_) =>
                        _emailFocus.requestFocus(),
                  ),
                ],
              )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            _buildSectionLabel(
              icon: Icons.admin_panel_settings_outlined,
              title: 'ACCOUNT ACCESS',
            ),

            const SizedBox(height: 11),

            _buildRoleSelector(),

            const SizedBox(height: 12),

            _buildTextField(
              controller: _emailController,
              focusNode: _emailFocus,
              label: 'Email Address',
              hint: 'Enter your email',
              icon: Icons.email_outlined,
              keyboardType:
              TextInputType.emailAddress,
              validator: _validateEmail,
              textInputAction:
              TextInputAction.next,
              onSubmitted: (_) =>
                  _passwordFocus.requestFocus(),
            ),

            const SizedBox(height: 12),

            _buildTextField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              label: 'Password',
              hint: 'Create a secure password',
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePass,
              validator: _validatePassword,
              textInputAction:
              TextInputAction.next,
              onSubmitted: (_) =>
                  _confirmPasswordFocus.requestFocus(),
              suffix: IconButton(
                tooltip: _obscurePass
                    ? 'Show password'
                    : 'Hide password',
                onPressed: () {
                  setState(() {
                    _obscurePass = !_obscurePass;
                  });
                },
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _mutedText,
                  size: 19,
                ),
              ),
            ),

            if (_passwordController.text.isNotEmpty)
              _buildPasswordStrength(),

            const SizedBox(height: 12),

            _buildTextField(
              controller:
              _confirmPasswordController,
              focusNode:
              _confirmPasswordFocus,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              icon: Icons.lock_outline_rounded,
              obscure: _obscureConfirmPass,
              validator:
              _validateConfirmPassword,
              textInputAction:
              TextInputAction.done,
              onSubmitted: (_) =>
                  _registerUser(),
              suffix: IconButton(
                tooltip:
                _obscureConfirmPass
                    ? 'Show password'
                    : 'Hide password',
                onPressed: () {
                  setState(() {
                    _obscureConfirmPass =
                    !_obscureConfirmPass;
                  });
                },
                icon: Icon(
                  _obscureConfirmPass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _mutedText,
                  size: 19,
                ),
              ),
            ),

            const SizedBox(height: 22),

            _buildRegisterButton(),

            const SizedBox(height: 17),

            _buildDivider(),

            const SizedBox(height: 17),

            _buildGoogleButton(),

            const SizedBox(height: 19),

            _buildLoginHint(),

            const SizedBox(height: 16),

            _buildSecurityFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [
              _teal,
              _cyan,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: _cyan.withOpacity(0.20),
              blurRadius: 30,
            ),
          ],
        ),
        child: const Icon(
          Icons.local_hospital_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }

// ===========================================================================
// SECTION LABEL
// ===========================================================================

  Widget _buildSectionLabel({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: _cyan,
          size: 15,
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: GoogleFonts.inter(
            color: _cyan,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

// ===========================================================================
// ROLE SELECTOR
// ===========================================================================

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(0.075),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildRoleOption(
              role: 'surgeon',
              label: 'Surgeon',
              icon: Icons.medical_services_outlined,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildRoleOption(
              role: 'admin',
              label: 'Admin',
              icon: Icons.admin_panel_settings_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOption({
    required String role,
    required String label,
    required IconData icon,
  }) {
    final selected = _selectedRole == role;

    return GestureDetector(
      onTap: (_isLoading || _isGoogleLoading)
          ? null
          : () {
        HapticFeedback.selectionClick();

        setState(() {
          _selectedRole = role;
        });
      },
      child: AnimatedContainer(
        duration:
        const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          vertical: 11,
          horizontal: 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? _teal.withOpacity(0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? _cyan.withOpacity(0.30)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color:
              selected ? _cyan : _mutedText,
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.inter(
                color:
                selected ? _white : _secondaryText,
                fontSize: 11.5,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

// ===========================================================================
// TEXT FIELD
// ===========================================================================

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final focused = focusNode.hasFocus;

    return AnimatedContainer(
      duration:
      const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: focused
            ? [
          BoxShadow(
            color: _cyan.withOpacity(0.06),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ]
            : null,
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        autocorrect: false,
        enableSuggestions: false,
        style: GoogleFonts.inter(
          color: _white,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: _cyan,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: _mutedText,
            fontSize: 11.5,
          ),
          labelStyle: GoogleFonts.inter(
            color: focused
                ? _cyan
                : _secondaryText,
            fontSize: 11.5,
          ),
          floatingLabelStyle:
          GoogleFonts.inter(
            color: _cyan,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
          prefixIcon: Icon(
            icon,
            color:
            focused ? _cyan : _mutedText,
            size: 18,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor:
          Colors.white.withOpacity(0.035),
          contentPadding:
          const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 15,
          ),
          enabledBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(14),
            borderSide: BorderSide(
              color:
              Colors.white.withOpacity(0.075),
            ),
          ),
          focusedBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(14),
            borderSide:
            const BorderSide(
              color: _cyan,
              width: 1.1,
            ),
          ),
          errorBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(14),
            borderSide: BorderSide(
              color:
              _danger.withOpacity(0.55),
            ),
          ),
          focusedErrorBorder:
          OutlineInputBorder(
            borderRadius:
            BorderRadius.circular(14),
            borderSide:
            const BorderSide(
              color: _danger,
              width: 1.1,
            ),
          ),
          errorStyle: GoogleFonts.inter(
            color: _danger,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

// ===========================================================================
// PASSWORD STRENGTH
// ===========================================================================

  Widget _buildPasswordStrength() {
    final strength = _passwordStrength();
    final color = _passwordStrengthColor();

    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        left: 3,
        right: 3,
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(
              4,
                  (index) {
                final segment =
                    (index + 1) / 4;

                return Expanded(
                  child: AnimatedContainer(
                    duration:
                    const Duration(
                      milliseconds: 250,
                    ),
                    margin:
                    EdgeInsets.only(
                      right:
                      index == 3 ? 0 : 4,
                    ),
                    height: 3,
                    decoration:
                    BoxDecoration(
                      color: strength >= segment
                          ? color
                          : Colors.white
                          .withOpacity(
                        0.08,
                      ),
                      borderRadius:
                      BorderRadius
                          .circular(10),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                _passwordStrengthText(),
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 9,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Use uppercase, numbers & symbols',
                style: GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// ===========================================================================
// REGISTER BUTTON
// ===========================================================================

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 53,
      child: FilledButton(
        onPressed:
        (_isLoading || _isGoogleLoading)
            ? null
            : _registerUser,
        style: FilledButton.styleFrom(
          backgroundColor: _teal,
          disabledBackgroundColor:
          _teal.withOpacity(0.40),
          foregroundColor: Colors.white,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration:
          const Duration(milliseconds: 200),
          child: _isLoading
              ? const SizedBox(
            key: ValueKey('loading'),
            width: 20,
            height: 20,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : Row(
            key: const ValueKey(
              'register',
            ),
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Create Account',
                style:
                GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// ===========================================================================
// DIVIDER
// ===========================================================================

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color:
            Colors.white.withOpacity(0.065),
          ),
        ),
        Padding(
          padding:
          const EdgeInsets.symmetric(
            horizontal: 13,
          ),
          child: Text(
            'OR',
            style: GoogleFonts.inter(
              color: _mutedText,
              fontSize: 9,
              fontWeight:
              FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color:
            Colors.white.withOpacity(0.065),
          ),
        ),
      ],
    );
  }

// ===========================================================================
// GOOGLE BUTTON
// ===========================================================================

  Widget _buildGoogleButton() {
    final windowsUnsupported =
        !kIsWeb && Platform.isWindows;

    return SizedBox(
      width: double.infinity,
      height: 53,
      child: OutlinedButton(
        onPressed:
        (_isLoading ||
            _isGoogleLoading ||
            windowsUnsupported)
            ? null
            : _signUpWithGoogle,
        style:
        OutlinedButton.styleFrom(
          foregroundColor: _white,
          disabledForegroundColor:
          _mutedText.withOpacity(0.55),
          side: BorderSide(
            color: Colors.white.withOpacity(
              windowsUnsupported
                  ? 0.035
                  : 0.09,
            ),
          ),
          backgroundColor:
          Colors.white.withOpacity(
            windowsUnsupported
                ? 0.015
                : 0.025,
          ),
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
        ),
        child: AnimatedSwitcher(
          duration:
          const Duration(milliseconds: 200),
          child: _isGoogleLoading
              ? const SizedBox(
            key: ValueKey(
              'google-loading',
            ),
            width: 20,
            height: 20,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
              color: _cyan,
            ),
          )
              : Row(
            key: const ValueKey(
              'google',
            ),
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              _buildGoogleIcon(),
              const SizedBox(width: 9),
              Text(
                windowsUnsupported
                    ? 'Google unavailable on Windows'
                    : 'Sign up with Google',
                style:
                GoogleFonts.inter(
                  color:
                  windowsUnsupported
                      ? _mutedText
                      : _white,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 23,
      height: 23,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: GoogleFonts.inter(
          color:
          const Color(0xFF4285F4),
          fontSize: 14,
          fontWeight:
          FontWeight.w800,
        ),
      ),
    );
  }

// ===========================================================================
// LOGIN HINT
// ===========================================================================

  Widget _buildLoginHint() {
    return Center(
      child: TextButton(
        onPressed:
        (_isLoading ||
            _isGoogleLoading)
            ? null
            : () {
          HapticFeedback
              .lightImpact();
          Navigator.pop(context);
        },
        style: TextButton.styleFrom(
          foregroundColor: _cyan,
          padding:
          const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 4,
          ),
          minimumSize: Size.zero,
          tapTargetSize:
          MaterialTapTargetSize
              .shrinkWrap,
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text:
                'Already have an account? ',
                style:
                GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 11,
                ),
              ),
              TextSpan(
                text: 'Sign in',
                style:
                GoogleFonts.inter(
                  color: _cyan,
                  fontSize: 11,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// ===========================================================================
// SECURITY FOOTER
// ===========================================================================

  Widget _buildSecurityFooter() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color:
        _success.withOpacity(0.035),
        borderRadius:
        BorderRadius.circular(11),
        border: Border.all(
          color:
          _success.withOpacity(0.07),
        ),
      ),
      child: Row(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: _success,
            size: 14,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Secure registration • Firebase authentication • Role-based access',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _mutedText,
                fontSize: 9,
                fontWeight:
                FontWeight.w500,
              ),
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
    _nameController.dispose();
    _phoneController.dispose();
    _hospitalController.dispose();
    _specializationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    _nameFocus.dispose();
    _phoneFocus.dispose();
    _hospitalFocus.dispose();
    _specializationFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();

    _pageController.dispose();
    _orbController.dispose();
    _pulseController.dispose();

    super.dispose();
  }
}

// =============================================================================
// BACKGROUND GRID
// =============================================================================

class _MedicalGridPainter extends CustomPainter {
  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    final paint = Paint()
      ..color =
      Colors.white.withOpacity(0.018)
      ..strokeWidth = 0.7;

    const spacing = 42.0;

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
