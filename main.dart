import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/login_page.dart';
import 'screens/surgeon/surgeon_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurgiAssist',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 🌀 SPLASH SCREEN WITH AUTH CHECK
class SplashScreen extends StatefulWidget {
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    // Check authentication state while splash animates
    Timer(const Duration(seconds: 3), () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
      } else {
        final role = await getUserRole(user.uid);
        if (role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AdminDashboard()),
          );
        } else if (role == 'surgeon') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => SurgeonDashboard()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Center(child: Text('Invalid role detected')),
              ),
            ),
          );
        }
      }
    });
  }

  Future<String?> getUserRole(String uid) async {
    final doc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data()?['role'];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ✨ UI: Gradient + Glow + Shimmer Logo Text
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Circular glowing logo
                Container(
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withOpacity(0.8),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo.png', // 🔥 Place your logo in assets folder
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 40),

                // App Name with shimmer effect
                Shimmer.fromColors(
                  baseColor: Colors.white,
                  highlightColor: Colors.tealAccent,
                  child: Text(
                    "SurgiAssist",
                    style: GoogleFonts.poppins(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "AI-Powered Surgical Assistance",
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 80),

                // Animated Loading Indicator
                SizedBox(
                  height: 40,
                  width: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
