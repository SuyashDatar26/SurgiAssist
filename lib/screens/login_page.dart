import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'admin/admin_dashboard.dart';
import 'register_page.dart';
import 'surgeon/surgeon_dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
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
  static const Color _danger = Color(0xFFFB7185);

// ===========================================================================
// CONTROLLERS
// ===========================================================================

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

// ===========================================================================
// STATE
// ===========================================================================

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  bool _emailFocused = false;
  bool _passwordFocused = false;

  String? _errorMessage;

// ===========================================================================
// GOOGLE SIGN-IN
// ===========================================================================

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

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
      begin: 0.96,
      end: 1.04,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _setupFocusListeners() {
    _emailFocus.addListener(() {
      if (!mounted) return;

      setState(() {
        _emailFocused = _emailFocus.hasFocus;
      });
    });

    _passwordFocus.addListener(() {
      if (!mounted) return;

      setState(() {
        _passwordFocused = _passwordFocus.hasFocus;
      });
    });
  }

// ===========================================================================
// GOOGLE INITIALIZATION
// ===========================================================================

  Future<void> _initializeGoogleSignIn() async {
    try {
      // Google Sign-In is not supported on Windows desktop.
      if (!kIsWeb && Platform.isWindows) {
        return;
      }

      await _googleSignIn.initialize(
        serverClientId:
        '431648024865-8moebllati50grqoa84cjr32k1l3fnsb.apps.googleusercontent.com',
      );

      if (!mounted) return;

      setState(() {
        _googleInitialized = true;
      });

      debugPrint('Google Sign-In initialized successfully.');
    } catch (e) {
      debugPrint('Google Sign-In initialization error: $e');
    }
  }

// ===========================================================================
// EMAIL / PASSWORD LOGIN
// ===========================================================================

  Future<void> _loginUser() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showError('Please enter your email address.');
      _emailFocus.requestFocus();
      return;
    }

    if (!_isValidEmail(email)) {
      _showError('Please enter a valid email address.');
      _emailFocus.requestFocus();
      return;
    }

    if (password.isEmpty) {
      _showError('Please enter your password.');
      _passwordFocus.requestFocus();
      return;
    }

    if (_isLoading || _isGoogleLoading) return;

    HapticFeedback.lightImpact();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userCred =
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _routeUserByRole(userCred.user!);
    } on FirebaseAuthException catch (e) {
      _handleFirebaseAuthError(e);
    } catch (e) {
      _showError('Something went wrong. Please try again.');
      debugPrint('LOGIN ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

// ===========================================================================
// GOOGLE LOGIN
// ===========================================================================

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();

    if (_isLoading || _isGoogleLoading) return;

// Windows desktop is not supported by google_sign_in.
    if (!kIsWeb && Platform.isWindows) {
      _showError(
        'Google Sign-In is available on supported mobile and web platforms. '
            'Please use email and password on Windows.',
      );
      return;
    }

    if (!_googleInitialized) {
      _showError(
        'Google Sign-In is still initializing. Please try again in a moment.',
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
          'Google Sign-In is not available on this platform configuration.',
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

      final userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'google-user-null',
          message: 'Unable to retrieve the Google account.',
        );
      }

      await _routeUserByRole(user);
    } on GoogleSignInException catch (e) {
      debugPrint(
        'Google Sign-In exception: ${e.code} - ${e.description}',
      );

      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showError(
          e.description ?? 'Google Sign-In failed. Please try again.',
        );
      }
    } on FirebaseAuthException catch (e) {
      _handleFirebaseAuthError(e);
    } catch (e) {
      debugPrint('GOOGLE LOGIN ERROR: $e');
      _showError('Google Sign-In failed. Please try again.');
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

  Future<void> _routeUserByRole(User user) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      await FirebaseAuth.instance.signOut();

      _showError(
        'Your account is not registered in SurgiAssist. '
            'Please contact the administrator.',
      );

      return;
    }

    final data = userDoc.data();

    final role = data?['role']
        ?.toString()
        .trim()
        .toLowerCase();

    if (!mounted) return;

    if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, secondaryAnimation) =>
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
          transitionDuration: const Duration(milliseconds: 450),
        ),
      );
    } else if (role == 'surgeon') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, secondaryAnimation) =>
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
          transitionDuration: const Duration(milliseconds: 450),
        ),
      );
    } else {
      await FirebaseAuth.instance.signOut();

      _showError(
        'No valid role is assigned to this account. '
            'Please contact the administrator.',
      );
    }
  }

// ===========================================================================
// AUTH ERROR HANDLING
// ===========================================================================

  void _handleFirebaseAuthError(FirebaseAuthException e) {
    String message;

    switch (e.code) {
      case 'invalid-email':
        message = 'The email address is not valid.';
        break;

      case 'user-not-found':
        message = 'No account was found with this email address.';
        break;

      case 'wrong-password':
      case 'invalid-credential':
        message = 'Incorrect email or password.';
        break;

      case 'user-disabled':
        message = 'This account has been disabled.';
        break;

      case 'too-many-requests':
        message =
        'Too many unsuccessful attempts. Please try again later.';
        break;

      case 'network-request-failed':
        message =
        'Network connection failed. Please check your internet.';
        break;

      case 'operation-not-allowed':
        message =
        'This sign-in method is currently disabled.';
        break;

      default:
        message = e.message ?? 'Login failed. Please try again.';
    }

    _showError(message);
  }

// ===========================================================================
// VALIDATION
// ===========================================================================

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);
  }

// ===========================================================================
// ERROR MESSAGE
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

// ===========================================================================
// REGISTER
// ===========================================================================

  void _openRegister() {
    HapticFeedback.lightImpact();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) =>
            RegisterPage(),
        transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
            ) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
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

// Large cyan ambient orb
              Positioned(
                left: -170 + (value * 45),
                top: -170,
                child: _buildAmbientOrb(
                  size: 390,
                  color: _teal,
                ),
              ),

// Secondary cyan orb
              Positioned(
                right: -210 + (value * 55),
                bottom: -190,
                child: _buildAmbientOrb(
                  size: 430,
                  color: _cyan,
                ),
              ),

// Small upper-right glow
              Positioned(
                right: 70,
                top: 90 + (value * 25),
                child: _buildAmbientOrb(
                  size: 150,
                  color: _teal,
                ),
              ),

// Subtle grid
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
              color.withOpacity(0.14),
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
// RESPONSIVE LAYOUT
// ===========================================================================

  Widget _buildResponsiveLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= 1000) {
          return _buildDesktopLayout(constraints);
        }

        if (width >= 650) {
          return _buildTabletLayout(constraints);
        }

        return _buildMobileLayout(constraints);
      },
    );
  }

// ===========================================================================
// DESKTOP
// ===========================================================================

  Widget _buildDesktopLayout(BoxConstraints constraints) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 55,
          vertical: 35,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1180,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 6,
                child: _buildBrandPanel(),
              ),
              const SizedBox(width: 65),
              Expanded(
                flex: 5,
                child: _buildLoginCard(),
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

  Widget _buildTabletLayout(BoxConstraints constraints) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 40,
          vertical: 30,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 580,
          ),
          child: _buildLoginCard(),
        ),
      ),
    );
  }

// ===========================================================================
// MOBILE
// ===========================================================================

  Widget _buildMobileLayout(BoxConstraints constraints) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          30,
        ),
        child: _buildLoginCard(
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
        _buildBrandLogo(),
        const SizedBox(height: 28),

        Text(
          'SurgiAssist',
          style: GoogleFonts.poppins(
            color: _white,
            fontSize: 46,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'AI-powered assistance for the\nmodern operating theatre.',
          style: GoogleFonts.poppins(
            color: _secondaryText,
            fontSize: 19,
            fontWeight: FontWeight.w400,
            height: 1.45,
          ),
        ),

        const SizedBox(height: 35),

        _buildFeature(
          icon: Icons.psychology_outlined,
          title: 'Intelligent Assistance',
          description:
          'Access AI-powered procedural information when you need it.',
        ),

        const SizedBox(height: 18),

        _buildFeature(
          icon: Icons.record_voice_over_outlined,
          title: 'Voice-Enabled Workflow',
          description:
          'Interact with patient and procedure information naturally.',
        ),

        const SizedBox(height: 18),

        _buildFeature(
          icon: Icons.security_outlined,
          title: 'Secure Clinical Environment',
          description:
          'Role-based access keeps administrative and surgical workflows separated.',
        ),

        const SizedBox(height: 40),

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
              'SECURE CLINICAL ACCESS',
              style: GoogleFonts.inter(
                color: _secondaryText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrandLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
// LOGIN CARD
// ===========================================================================

  Widget _buildLoginCard({
    bool mobile = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        mobile ? 22 : 30,
      ),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.94),
        borderRadius: BorderRadius.circular(
          mobile ? 24 : 28,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mobile) ...[
            Center(
              child: _buildBrandLogo(),
            ),
            const SizedBox(height: 20),
          ],

          Text(
            'Welcome back',
            style: GoogleFonts.poppins(
              color: _white,
              fontSize: mobile ? 25 : 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Sign in to continue to your clinical workspace.',
            style: GoogleFonts.inter(
              color: _secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 27),

// EMAIL
          _buildTextField(
            controller: _emailController,
            focusNode: _emailFocus,
            label: 'Email address',
            hint: 'Enter your registered email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) {
              _passwordFocus.requestFocus();
            },
          ),

          const SizedBox(height: 15),

// PASSWORD
          _buildTextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loginUser(),
            suffix: IconButton(
              tooltip:
              _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _mutedText,
                size: 19,
              ),
            ),
          ),

          const SizedBox(height: 23),

// EMAIL LOGIN BUTTON
          _buildLoginButton(),

          const SizedBox(height: 18),

          _buildDivider(),

          const SizedBox(height: 18),

// GOOGLE LOGIN
          _buildGoogleButton(),

          const SizedBox(height: 22),

// REGISTER
          _buildRegisterPrompt(),

          const SizedBox(height: 18),

// SECURITY FOOTER
          _buildSecurityFooter(),
        ],
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
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final bool focused =
    focusNode == _emailFocus ? _emailFocused : _passwordFocused;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: focused
            ? [
          BoxShadow(
            color: _cyan.withOpacity(0.07),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ]
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autocorrect: false,
        enableSuggestions: false,
        style: GoogleFonts.inter(
          color: _white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: _cyan,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: _mutedText,
            fontSize: 12,
          ),
          labelStyle: GoogleFonts.inter(
            color: focused ? _cyan : _secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: GoogleFonts.inter(
            color: _cyan,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          prefixIcon: Icon(
            icon,
            color: focused ? _cyan : _mutedText,
            size: 19,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.035),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.075),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(
              color: _cyan,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// LOGIN BUTTON
// ===========================================================================

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: (_isLoading || _isGoogleLoading)
            ? null
            : _loginUser,
        style: FilledButton.styleFrom(
          backgroundColor: _teal,
          disabledBackgroundColor: _teal.withOpacity(0.45),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isLoading
              ? const SizedBox(
            key: ValueKey('loading'),
            width: 21,
            height: 21,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : Row(
            key: const ValueKey('login'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.login_rounded,
                size: 19,
              ),
              const SizedBox(width: 9),
              Text(
                'Sign in',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
            color: Colors.white.withOpacity(0.065),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
          ),
          child: Text(
            'OR',
            style: GoogleFonts.inter(
              color: _mutedText,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withOpacity(0.065),
          ),
        ),
      ],
    );
  }

// ===========================================================================
// GOOGLE BUTTON
// ===========================================================================

  Widget _buildGoogleButton() {
    final bool windowsUnsupported =
        !kIsWeb && Platform.isWindows;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: (_isLoading ||
            _isGoogleLoading ||
            windowsUnsupported)
            ? null
            : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: _white,
          disabledForegroundColor: _mutedText.withOpacity(0.55),
          side: BorderSide(
            color: Colors.white.withOpacity(
              windowsUnsupported ? 0.035 : 0.09,
            ),
          ),
          backgroundColor: Colors.white.withOpacity(
            windowsUnsupported ? 0.015 : 0.025,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isGoogleLoading
              ? const SizedBox(
            key: ValueKey('google-loading'),
            width: 21,
            height: 21,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _cyan,
            ),
          )
              : Row(
            key: const ValueKey('google'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGoogleIcon(),
              const SizedBox(width: 10),
              Text(
                windowsUnsupported
                    ? 'Google unavailable on Windows'
                    : 'Continue with Google',
                style: GoogleFonts.inter(
                  color: windowsUnsupported
                      ? _mutedText
                      : _white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
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
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: GoogleFonts.inter(
          color: const Color(0xFF4285F4),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

// ===========================================================================
// REGISTER PROMPT
// ===========================================================================

  Widget _buildRegisterPrompt() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "Don't have an account?",
            style: GoogleFonts.inter(
              color: _mutedText,
              fontSize: 11.5,
            ),
          ),
          TextButton(
            onPressed: (_isLoading || _isGoogleLoading)
                ? null
                : _openRegister,
            style: TextButton.styleFrom(
              foregroundColor: _cyan,
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 4,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Create account',
              style: GoogleFonts.inter(
                color: _cyan,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

// ===========================================================================
// SECURITY FOOTER
// ===========================================================================

  Widget _buildSecurityFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: _success.withOpacity(0.035),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: _success.withOpacity(0.07),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: _success,
            size: 14,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Protected clinical access • Role-based authentication',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _mutedText,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
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
    _emailController.dispose();
    _passwordController.dispose();

    _emailFocus.dispose();
    _passwordFocus.dispose();

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
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.018)
      ..strokeWidth = 0.7;

    const double spacing = 42;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

