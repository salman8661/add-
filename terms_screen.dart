import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/gradient_button.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  _TermsScreenState createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _typingAnimation;
  static const String _welcomeText = 'Welcome to DoDay Messenger';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    print('TermsScreen: Initializing');
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _typingAnimation = IntTween(begin: 0, end: _welcomeText.length).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    print('TermsScreen: Disposing');
    _controller.dispose();
    super.dispose();
  }

  Future<void> _acceptTerms() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'termsAccepted': true, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        print('TermsScreen: Terms accepted for user ${user.uid}, navigating to LoginScreen');
        Navigator.pushReplacementNamed(context, '/login');
      } catch (e) {
        print('TermsScreen: Error saving terms acceptance: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } else {
      print('TermsScreen: No authenticated user, navigating to LoginScreen');
      Navigator.pushReplacementNamed(context, '/login');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    print('TermsScreen: Building UI');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.35,
            decoration: const BoxDecoration(
              color: Color(0xFFE3E3E3),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _typingAnimation,
                    builder: (context, child) {
                      String text = _welcomeText.substring(0, _typingAnimation.value);
                      return ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
                            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds);
                        },
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Image.asset(
                    'assets/images/logo.png',
                    height: 150,
                    width: 150,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, size: 150),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Terms and Services',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'By signing up, you agree to DoDay Messenger\'s Privacy Policy and Terms of Service. '
                        'We may update these terms periodically to reflect new features or changes in our services. '
                        'You will be notified of significant updates via the app or email.',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Last Updated: March 06, 2025',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),
                  GradientButton(
                    text: 'Accept and Continue',
                    onPressed: _acceptTerms,
                    isLoading: _isLoading,
                    gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}