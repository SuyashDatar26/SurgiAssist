import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin/admin_dashboard.dart';
import 'login_page.dart';
import 'surgeon/surgeon_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color deepNavy = Color(0xFF0B1F33);
  static const Color navyBlue = Color(0xFF123A56);
  static const Color surgicalTeal = Color(0xFF0E7490);
  static const Color medicalCyan = Color(0xFF22D3EE);

  static const Color white = Color(0xFFFFFFFF);
  static const Color mutedText = Color(0xFF9DB2C1);

  // ============================================================
  // ANIMATION CONTROLLERS
  // ============================================================

  late AnimationController _mainController;
  late AnimationController _orbitalController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _contentOpacity;
  late Animation<Offset> _contentSlide;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;

  // ============================================================
  // AUTH / LOADING STATE
  // ============================================================

  String _statusText = 'Initializing secure environment';

  bool _navigationStarted = false;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // ----------------------------------------------------------
    // MAIN SPLASH ANIMATION
    // ----------------------------------------------------------

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    );

    _logoScale = Tween<double>(
      begin: 0.65,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.0,
          0.55,
          curve: Curves.easeOutBack,
        ),
      ),
    );

    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.0,
          0.35,
          curve: Curves.easeOut,
        ),
      ),
    );

    _contentOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.30,
          0.80,
          curve: Curves.easeOut,
        ),
      ),
    );

    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.30,
          0.80,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _ringScale = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.0,
          0.65,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _ringOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(
          0.05,
          0.50,
          curve: Curves.easeOut,
        ),
      ),
    );

    // ----------------------------------------------------------
    // ORBITAL ROTATION
    // ----------------------------------------------------------

    _orbitalController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    // ----------------------------------------------------------
    // LOGO PULSE
    // ----------------------------------------------------------

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    // ----------------------------------------------------------
    // SHIMMER
    // ----------------------------------------------------------

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..repeat();

    // Start main animation.

    _mainController.forward();

    // Begin authentication process immediately.
    _initializeApplication();
  }

  // ============================================================
  // APPLICATION INITIALIZATION
  // ============================================================

  Future<void> _initializeApplication() async {
    try {
      if (mounted) {
        setState(() {
          _statusText = 'Checking authentication';
        });
      }

      // Small delay allows the initial animation to establish
      // before changing the status.

      await Future.delayed(
        const Duration(milliseconds: 650),
      );

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (mounted) {
          setState(() {
            _statusText = 'Preparing secure login';
          });
        }

        await Future.delayed(
          const Duration(milliseconds: 650),
        );

        _navigateToLogin();
        return;
      }

      if (mounted) {
        setState(() {
          _statusText = 'Verifying account permissions';
        });
      }

      final role = await _getUserRole(user.uid);

      if (!mounted) {
        return;
      }

      setState(() {
        _statusText = 'Loading your workspace';
      });

      await Future.delayed(
        const Duration(milliseconds: 600),
      );

      if (role == 'admin') {
        _navigateToAdmin();
      } else if (role == 'surgeon') {
        _navigateToSurgeon();
      } else {
        _navigateToInvalidRole();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusText = 'Unable to verify account';
      });

      await Future.delayed(
        const Duration(milliseconds: 900),
      );

      if (mounted) {
        _navigateToInvalidRole();
      }
    }
  }

  // ============================================================
  // FIRESTORE ROLE
  // ============================================================

  Future<String?> _getUserRole(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> document =
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    return document.data()?['role']?.toString().toLowerCase();
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _navigateToLogin() {
    if (_navigationStarted || !mounted) {
      return;
    }

    _navigationStarted = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (
            context,
            animation,
            secondaryAnimation,
            ) =>
        const LoginPage(),

        transitionDuration: const Duration(
          milliseconds: 650,
        ),

        reverseTransitionDuration: const Duration(
          milliseconds: 400,
        ),

        transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
            ) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _navigateToAdmin() {
    if (_navigationStarted || !mounted) {
      return;
    }

    _navigationStarted = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (
            context,
            animation,
            secondaryAnimation,
            ) =>
         AdminDashboard(),

        transitionDuration: const Duration(
          milliseconds: 650,
        ),

        transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
            ) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: child,
          );
        },
      ),
    );
  }

  void _navigateToSurgeon() {
    if (_navigationStarted || !mounted) {
      return;
    }

    _navigationStarted = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (
            context,
            animation,
            secondaryAnimation,
            ) =>
        const SurgeonDashboard(),

        transitionDuration: const Duration(
          milliseconds: 650,
        ),

        transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
            ) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: child,
          );
        },
      ),
    );
  }

  void _navigateToInvalidRole() {
    if (_navigationStarted || !mounted) {
      return;
    }

    _navigationStarted = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const _InvalidRoleScreen(),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _navigationTimer?.cancel();

    _mainController.dispose();
    _orbitalController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepNavy,

      body: Container(
        width: double.infinity,
        height: double.infinity,

        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF071521),
              deepNavy,
              Color(0xFF0C2B42),
            ],
            stops: [
              0.0,
              0.52,
              1.0,
            ],
          ),
        ),

        child: Stack(
          children: [
            // --------------------------------------------------
            // BACKGROUND DECORATION
            // --------------------------------------------------

            const _BackgroundDecoration(),

            // --------------------------------------------------
            // MAIN CONTENT
            // --------------------------------------------------

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),

                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                  ),

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAnimatedLogo(),

                      const SizedBox(height: 42),

                      _buildAnimatedBrand(),

                      const SizedBox(height: 16),

                      _buildTagline(),

                      const SizedBox(height: 58),

                      _buildLoadingSection(),
                    ],
                  ),
                ),
              ),
            ),

            // --------------------------------------------------
            // VERSION / SECURITY LABEL
            // --------------------------------------------------

            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _buildBottomLabel(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOGO
  // ============================================================

  Widget _buildAnimatedLogo() {
    return FadeTransition(
      opacity: _logoOpacity,

      child: ScaleTransition(
        scale: _logoScale,

        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pulseController,
            _orbitalController,
          ]),

          builder: (context, child) {
            final pulseValue = Curves.easeInOut.transform(
              _pulseController.value,
            );

            return SizedBox(
              width: 190,
              height: 190,

              child: Stack(
                alignment: Alignment.center,
                children: [
                  // --------------------------------------------
                  // OUTER GLOW
                  // --------------------------------------------

                  Container(
                    width: 145 + (pulseValue * 12),
                    height: 145 + (pulseValue * 12),

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      boxShadow: [
                        BoxShadow(
                          color: medicalCyan.withOpacity(
                            0.10 + (pulseValue * 0.12),
                          ),
                          blurRadius: 50 + (pulseValue * 10),
                          spreadRadius: 8,
                        ),

                        BoxShadow(
                          color: surgicalTeal.withOpacity(
                            0.12,
                          ),
                          blurRadius: 70,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                  // --------------------------------------------
                  // ORBITAL RING
                  // --------------------------------------------

                  Transform.rotate(
                    angle: _orbitalController.value * 2 * math.pi,

                    child: CustomPaint(
                      size: const Size(178, 178),

                      painter: _OrbitalRingPainter(
                        color: medicalCyan,
                        secondaryColor: surgicalTeal,
                      ),
                    ),
                  ),

                  // --------------------------------------------
                  // INNER CIRCLE
                  // --------------------------------------------

                  Container(
                    width: 132,
                    height: 132,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF174765),
                          Color(0xFF0B263C),
                        ],
                      ),

                      border: Border.all(
                        color: medicalCyan.withOpacity(0.28),
                        width: 1.2,
                      ),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),

                    child: Padding(
                      padding: const EdgeInsets.all(16),

                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',

                          fit: BoxFit.contain,

                          errorBuilder: (
                              context,
                              error,
                              stackTrace,
                              ) {
                            return const Icon(
                              Icons.local_hospital_rounded,
                              size: 55,
                              color: medicalCyan,
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // --------------------------------------------
                  // AI STATUS DOT
                  // --------------------------------------------

                  Positioned(
                    right: 23,
                    bottom: 22,

                    child: Container(
                      width: 18,
                      height: 18,

                      decoration: BoxDecoration(
                        shape: BoxShape.circle,

                        color: medicalCyan,

                        border: Border.all(
                          color: deepNavy,
                          width: 4,
                        ),

                        boxShadow: [
                          BoxShadow(
                            color: medicalCyan.withOpacity(0.8),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // BRAND NAME
  // ============================================================

  Widget _buildAnimatedBrand() {
    return FadeTransition(
      opacity: _contentOpacity,

      child: SlideTransition(
        position: _contentSlide,

        child: AnimatedBuilder(
          animation: _shimmerController,

          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (bounds) {
                final shimmerPosition =
                    (_shimmerController.value * 3) - 1;

                return LinearGradient(
                  begin: Alignment(-1.0 + shimmerPosition, 0),
                  end: Alignment(shimmerPosition + 1.0, 0),

                  colors: const [
                    white,
                    white,
                    medicalCyan,
                    white,
                    white,
                  ],

                  stops: const [
                    0.0,
                    0.35,
                    0.5,
                    0.65,
                    1.0,
                  ],
                ).createShader(bounds);
              },

              blendMode: BlendMode.srcIn,

              child: Text(
                'SurgiAssist',

                textAlign: TextAlign.center,

                style: GoogleFonts.poppins(
                  fontSize: 39,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // TAGLINE
  // ============================================================

  Widget _buildTagline() {
    return FadeTransition(
      opacity: _contentOpacity,

      child: SlideTransition(
        position: _contentSlide,

        child: Column(
          children: [
            Text(
              'AI-POWERED SURGICAL ASSISTANCE',

              textAlign: TextAlign.center,

              style: GoogleFonts.poppins(
                color: medicalCyan.withOpacity(0.95),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Intelligent information when every second matters.',

              textAlign: TextAlign.center,

              style: GoogleFonts.poppins(
                color: mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOADING SECTION
  // ============================================================

  Widget _buildLoadingSection() {
    return FadeTransition(
      opacity: _contentOpacity,

      child: SizedBox(
        width: 290,

        child: Column(
          children: [
            // --------------------------------------------
            // STATUS
            // --------------------------------------------

            AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 300,
              ),

              transitionBuilder: (
                  child,
                  animation,
                  ) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },

              child: Text(
                _statusText,

                key: ValueKey<String>(_statusText),

                textAlign: TextAlign.center,

                style: GoogleFonts.poppins(
                  color: mutedText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------
            // PROGRESS TRACK
            // --------------------------------------------

            Container(
              height: 3,

              width: double.infinity,

              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
              ),

              child: AnimatedBuilder(
                animation: _mainController,

                builder: (context, child) {
                  return Align(
                    alignment: Alignment.centerLeft,

                    child: FractionallySizedBox(
                      widthFactor: math.max(
                        0.08,
                        _mainController.value,
                      ),

                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              surgicalTeal,
                              medicalCyan,
                            ],
                          ),

                          borderRadius: BorderRadius.circular(20),

                          boxShadow: [
                            BoxShadow(
                              color: medicalCyan.withOpacity(0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 19),

            // --------------------------------------------
            // LOADING DOTS
            // --------------------------------------------

            _AnimatedLoadingDots(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BOTTOM LABEL
  // ============================================================

  Widget _buildBottomLabel() {
    return FadeTransition(
      opacity: _contentOpacity,

      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: mutedText.withOpacity(0.65),
              ),

              const SizedBox(width: 6),

              Text(
                'SECURE CLINICAL ENVIRONMENT',

                style: GoogleFonts.poppins(
                  color: mutedText.withOpacity(0.65),
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Text(
            'SurgiAssist',

            style: GoogleFonts.poppins(
              color: mutedText.withOpacity(0.35),
              fontSize: 8.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// BACKGROUND DECORATION
// ================================================================

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          // ----------------------------------------------
          // TOP RIGHT GLOW
          // ----------------------------------------------

          Positioned(
            top: -150,
            right: -120,

            child: Container(
              width: 400,
              height: 400,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0E7490).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ----------------------------------------------
          // BOTTOM LEFT GLOW
          // ----------------------------------------------

          Positioned(
            bottom: -180,
            left: -150,

            child: Container(
              width: 450,
              height: 450,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22D3EE).withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ----------------------------------------------
          // SUBTLE GRID
          // ----------------------------------------------

          Positioned.fill(
            child: CustomPaint(
              painter: _MedicalGridPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// ORBITAL RING PAINTER
// ================================================================

class _OrbitalRingPainter extends CustomPainter {
  final Color color;
  final Color secondaryColor;

  const _OrbitalRingPainter({
    required this.color,
    required this.secondaryColor,
  });

  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius = size.width / 2 - 7;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          secondaryColor.withOpacity(0.25),
          color.withOpacity(0.95),
          Colors.transparent,
          color.withOpacity(0.25),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.drawArc(
      rect,
      0,
      math.pi * 1.35,
      false,
      paint,
    );

    final secondaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = secondaryColor.withOpacity(0.20);

    canvas.drawArc(
      rect,
      math.pi * 1.5,
      math.pi * 0.55,
      false,
      secondaryPaint,
    );
  }

  @override
  bool shouldRepaint(
      covariant _OrbitalRingPainter oldDelegate,
      ) {
    return oldDelegate.color != color ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}

// ================================================================
// MEDICAL GRID PAINTER
// ================================================================

class _MedicalGridPainter extends CustomPainter {
  @override
  void paint(
      Canvas canvas,
      Size size,
      ) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.018)
      ..strokeWidth = 0.6;

    const double spacing = 42;

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

// ================================================================
// ANIMATED LOADING DOTS
// ================================================================

class _AnimatedLoadingDots extends StatefulWidget {
  @override
  State<_AnimatedLoadingDots> createState() =>
      _AnimatedLoadingDotsState();
}

class _AnimatedLoadingDotsState
    extends State<_AnimatedLoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(
        milliseconds: 1100,
      ),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,

      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,

          children: List.generate(
            3,
                (index) {
              final delay = index / 3;

              double value =
                  (_controller.value + delay) % 1.0;

              value = Curves.easeInOut.transform(value);

              final scale =
                  0.65 + (math.sin(value * math.pi) * 0.35);

              final opacity =
                  0.35 + (math.sin(value * math.pi) * 0.65);

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 3,
                ),

                child: Transform.scale(
                  scale: scale,

                  child: Opacity(
                    opacity: opacity,

                    child: Container(
                      width: 5,
                      height: 5,

                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF22D3EE),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ================================================================
// INVALID ROLE SCREEN
// ================================================================

class _InvalidRoleScreen extends StatelessWidget {
  const _InvalidRoleScreen();

  @override
  Widget build(BuildContext context) {
    const Color deepNavy = Color(0xFF0B1F33);
    const Color surgicalTeal = Color(0xFF0E7490);
    const Color critical = Color(0xFFDC2626);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),

          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),

            child: Card(
              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(
                  color: Color(0xFFE2E8ED),
                ),
              ),

              child: Padding(
                padding: const EdgeInsets.all(32),

                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    Container(
                      width: 72,
                      height: 72,

                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: critical.withOpacity(0.08),
                      ),

                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: critical,
                        size: 34,
                      ),
                    ),

                    const SizedBox(height: 22),

                    Text(
                      'Account Configuration Issue',

                      textAlign: TextAlign.center,

                      style: GoogleFonts.poppins(
                        color: deepNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Your account does not have a valid SurgiAssist role assigned. Please contact your administrator.',

                      textAlign: TextAlign.center,

                      style: GoogleFonts.poppins(
                        color: const Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 26),

                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton.icon(
                        onPressed: () {
                          FirebaseAuth.instance.signOut();

                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                                (route) => false,
                          );
                        },

                        icon: const Icon(
                          Icons.logout_rounded,
                          size: 18,
                        ),

                        label: const Text(
                          'Return to Login',
                        ),

                        style: ElevatedButton.styleFrom(
                          backgroundColor: deepNavy,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'SurgiAssist',

                      style: GoogleFonts.poppins(
                        color: surgicalTeal,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}