import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigateBasedOnAuth());
  }

  Future<void> _navigateBasedOnAuth() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 5), onTimeout: () => null);

    if (!mounted) return;

    if (user != null) {
      await authProvider.setCurrentUser(user);
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!doc.exists || doc.data()?['termsAccepted'] != true) {
        Navigator.pushReplacementNamed(context, '/terms');
      } else if (!user.emailVerified && user.email != null) {
        Navigator.pushReplacementNamed(context, '/email-verification');
      } else if (doc.data()?['username'] != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/profile-setup');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: themeProvider.themeData.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', height: 150, width: 150, errorBuilder: (_, __, ___) => const Icon(Icons.chat_bubble_outline, size: 150)),
            const SizedBox(height: 20),
            const Text('DoDay Messenger', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}