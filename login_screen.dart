import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordObscured = true;
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    print('LoginScreen: Initializing');
  }

  @override
  void dispose() {
    print('LoginScreen: Disposing');
    _identifierController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String input) => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(input);
  bool _isValidPassword(String input) => input.length >= 6;
  bool _isValidUsername(String input) => input.length >= 3 && RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(input);

  void _togglePasswordVisibility() {
    if (!mounted) return;
    setState(() => _isPasswordObscured = !_isPasswordObscured);
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org'));
      final ipAddress = response.statusCode == 200 ? response.body : 'Unknown';

      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown';
      String deviceId = DateTime.now().millisecondsSinceEpoch.toString();
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model ?? 'Unknown';
        deviceId = androidInfo.id ?? deviceId;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.utsname.machine ?? 'Unknown';
        deviceId = iosInfo.identifierForVendor ?? deviceId;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      String location = 'Disabled';
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) location = 'Denied';
        } else if (permission == LocationPermission.deniedForever) {
          location = 'Denied Forever';
        } else {
          final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
          location = 'Lat: ${position.latitude}, Long: ${position.longitude}';
        }
      }

      return {
        'ip': ipAddress,
        'deviceName': deviceName,
        'deviceId': deviceId,
        'location': location,
        'timestamp': FieldValue.serverTimestamp(),
      };
    } catch (e) {
      print('LoginScreen: Error getting device info: $e');
      return {
        'ip': 'Unknown',
        'deviceName': 'Unknown',
        'deviceId': DateTime.now().millisecondsSinceEpoch.toString(),
        'location': 'Error',
        'timestamp': FieldValue.serverTimestamp(),
      };
    }
  }

  Future<void> _saveDeviceInfo(String uid) async {
    try {
      final deviceInfo = await _getDeviceInfo();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceInfo['deviceId'])
          .set(deviceInfo, SetOptions(merge: true));
      print('LoginScreen: Device info saved for device: ${deviceInfo['deviceId']}');
    } catch (e) {
      print('LoginScreen: Error saving device info: $e');
      if (mounted) setState(() => _errorMessage = 'Failed to save device info: $e');
    }
  }

  Future<void> _navigateAfterLogin(User user) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      print("LoginScreen: Firestore doc exists: ${doc.exists}, data: ${doc.data()}");
      if (!user.emailVerified && user.email != null) {
        print("LoginScreen: Email not verified for user: ${user.uid}");
        await user.sendEmailVerification();
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              final theme = Provider.of<ThemeProvider>(dialogContext).themeData;
              return AlertDialog(
                backgroundColor: theme.cardColor,
                title: Text('Email Verification Required', style: theme.textTheme.headlineMedium),
                content: Text(
                  'Your email (${user.email}) is not verified. A verification email has been sent. Please verify to proceed.',
                  style: theme.textTheme.bodyMedium,
                ),
                actions: [
                  TextButton(
                    child: const Text('OK', style: TextStyle(color: Colors.blue)),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Provider.of<customAuth.CustomAuthProvider>(context, listen: false).signOut();
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                          _identifierController.clear();
                          _passwordController.clear();
                          _usernameController.clear();
                          _isSignUp = false;
                        });
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
      } else if (!doc.exists || doc.data()?['termsAccepted'] != true) {
        print("LoginScreen: Terms not accepted or no doc, navigating to TermsScreen");
        Navigator.pushReplacementNamed(context, '/terms');
      } else if (doc.data()?['username'] != null) {
        print("LoginScreen: User profile complete, navigating to HomeScreen");
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        print("LoginScreen: User profile incomplete, navigating to ProfileSetupScreen");
        Navigator.pushReplacementNamed(context, '/profile-setup');
      }
    } catch (e) {
      print('LoginScreen: Error in navigation: $e');
      if (mounted) setState(() => _errorMessage = 'Navigation error: $e');
    }
  }

  Future<void> _handleAuth() async {
    if (_isLoading) {
      if (mounted) setState(() => _errorMessage = 'Please wait for the current request to complete.');
      return;
    }

    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isLoading = true;
      });
    }

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (identifier.isEmpty) {
      if (mounted) setState(() {
        _errorMessage = 'Please enter a username or email';
        _isLoading = false;
      });
      return;
    }
    if (!_isValidPassword(password)) {
      if (mounted) setState(() {
        _errorMessage = 'Password must be at least 6 characters';
        _isLoading = false;
      });
      return;
    }
    if (_isSignUp && !_isValidUsername(username)) {
      if (mounted) setState(() {
        _errorMessage = 'Username must be 3+ characters (letters, numbers, underscores only)';
        _isLoading = false;
      });
      return;
    }
    if (_isSignUp && !_isValidEmail(identifier)) {
      if (mounted) setState(() {
        _errorMessage = 'Please enter a valid email for sign-up';
        _isLoading = false;
      });
      return;
    }

    try {
      final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
      if (_isSignUp) {
        print("LoginScreen: Attempting to sign up with email: $identifier");
        await authProvider.signUpWithEmailAndPassword(identifier, password, username);
        final user = authProvider.currentUser;
        if (user != null) {
          print("LoginScreen: Sign-up successful for user: ${user.uid}");
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'username': username,
            'email': identifier,
            'termsAccepted': false,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          await _saveDeviceInfo(user.uid);
          await _navigateAfterLogin(user);
          if (mounted) Navigator.pushReplacementNamed(context, '/email-verification');
        }
      } else {
        print("LoginScreen: Attempting sign-in with identifier: $identifier");
        if (_isValidEmail(identifier)) {
          await authProvider.signInWithEmailAndPassword(identifier, password);
        } else {
          await authProvider.signInWithUsernameAndPassword(identifier, password);
        }
        final user = authProvider.currentUser;
        if (user != null) {
          await _saveDeviceInfo(user.uid);
          await _navigateAfterLogin(user);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        print("LoginScreen: FirebaseAuthException: $e");
        setState(() {
          _errorMessage = _getFriendlyErrorMessage(e);
          _isLoading = false;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) setState(() {
        _errorMessage = 'Firestore error: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        print("LoginScreen: Error during auth: $e");
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    if (mounted) {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          final theme = Provider.of<ThemeProvider>(context).themeData;
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text('Reset Password', style: theme.textTheme.headlineMedium),
            content: Text(
              'Choose how you want to reset your password:',
              style: theme.textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                child: const Text('Link via Email', style: TextStyle(color: Colors.blue)),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final identifier = _identifierController.text.trim();
                  if (_isValidEmail(identifier)) {
                    try {
                      final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
                      await authProvider.sendPasswordResetEmail(identifier);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Password reset email sent to $identifier')),
                        );
                      }
                    } catch (e) {
                      if (mounted) setState(() => _errorMessage = 'Error: $e');
                    }
                  } else {
                    if (mounted) setState(() => _errorMessage = 'Please enter a valid email');
                  }
                },
              ),
              TextButton(
                child: const Text('OTP via Phone', style: TextStyle(color: Colors.blue)),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (mounted) Navigator.pushNamed(context, '/forgot-password');
                },
              ),
            ],
          );
        },
      );
    }
  }

  String _getFriendlyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many requests. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email/username.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    print('LoginScreen: Building UI');
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
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
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isSignUp ? 'Sign Up' : 'Login',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Image.asset(
                      'assets/images/logo.png',
                      height: 120,
                      width: 120,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.chat_bubble_outline,
                        size: 120,
                        color: Colors.black,
                      ),
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
                    if (_isSignUp)
                      CustomTextField(
                        controller: _usernameController,
                        labelText: 'Username',
                        fillColor: Colors.white24,
                        textColor: Colors.white,
                        keyboardType: TextInputType.text,
                        borderRadius: 16,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      ),
                    if (_isSignUp) const SizedBox(height: 16),
                    CustomTextField(
                      controller: _identifierController,
                      labelText: _isSignUp ? 'Email' : 'Username or Email',
                      fillColor: Colors.white24,
                      textColor: Colors.white,
                      keyboardType: TextInputType.text,
                      errorText: _errorMessage,
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _passwordController,
                      labelText: 'Password',
                      fillColor: Colors.white24,
                      textColor: Colors.white,
                      obscureText: _isPasswordObscured,
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      suffixIcon: IconButton(
                        icon: Image.asset(
                          _isPasswordObscured ? 'assets/hide.png' : 'assets/unhide.png',
                          width: 20,
                          height: 20,
                          color: Colors.white,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: _togglePasswordVisibility,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _errorMessage = null;
                      }),
                      child: Text(
                        _isSignUp ? 'Already have an account? Sign In' : 'New user? Sign Up',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 16,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showForgotPasswordDialog,
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 16,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    GradientButton(
                      text: 'Next',
                      onPressed: _handleAuth,
                      isLoading: _isLoading,
                      gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0183FB)),
                        ),
                      ),
                    if (_errorMessage != null && !_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}