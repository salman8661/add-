import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordObscured = true;

  @override
  void initState() {
    super.initState();
    print('AccountLoginScreen: Initializing');
    _requestSMSPermissions();
  }

  @override
  void dispose() {
    print('AccountLoginScreen: Disposing');
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestSMSPermissions() async {
    if (await Permission.sms.request().isGranted) {
      print('AccountLoginScreen: SMS permissions granted');
    } else {
      print('AccountLoginScreen: SMS permissions denied');
    }
  }

  bool _isValidEmail(String input) => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(input);
  bool _isValidPassword(String input) => input.length >= 6;

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
      print('AccountLoginScreen: Error getting device info: $e');
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
      print('AccountLoginScreen: Device info saved for device: ${deviceInfo['deviceId']}');
    } catch (e) {
      print('AccountLoginScreen: Error saving device info: $e');
      if (mounted) setState(() => _errorMessage = 'Failed to save device info: $e');
    }
  }

  Future<void> _navigateAfterLogin(User user) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      print("AccountLoginScreen: Firestore doc exists: ${doc.exists}, data: ${doc.data()}");
      if (!user.emailVerified && user.email != null) {
        print("AccountLoginScreen: Email not verified for user: ${user.uid}");
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
                          _emailController.clear();
                          _passwordController.clear();
                        });
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
      } else if (doc.exists && doc.data()?['username'] != null) {
        print("AccountLoginScreen: User profile exists with username: ${doc.data()!['username']}, navigating to HomeScreen");
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        print("AccountLoginScreen: User profile incomplete (no username), navigating to ProfileSetupScreen");
        Navigator.pushReplacementNamed(context, '/profile-setup');
      }
    } catch (e) {
      print('AccountLoginScreen: Error in navigation: $e');
      if (mounted) setState(() => _errorMessage = 'Navigation error: $e');
    }
  }

  Future<void> _handleEmailLogin() async {
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

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!_isValidEmail(email)) {
      if (mounted) setState(() {
        _errorMessage = 'Please enter a valid email';
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

    try {
      final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
      await authProvider.signInWithEmailAndPassword(email, password); // This now saves password to Firestore
      final user = authProvider.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        List<String> accountUids = prefs.getStringList('account_uids') ?? [];
        if (!accountUids.contains(user.uid)) {
          accountUids.add(user.uid);
          await prefs.setStringList('account_uids', accountUids);
        }
        await prefs.setString('account_${user.uid}_email', email);
        await prefs.setString('account_${user.uid}_password', password);
        await _saveDeviceInfo(user.uid);
        await _navigateAfterLogin(user);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        print("AccountLoginScreen: FirebaseAuthException during email auth: $e");
        setState(() {
          _errorMessage = _getFriendlyErrorMessage(e);
          _isLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        print("AccountLoginScreen: Error signing in with email/password: $e");
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAutoSignIn(User user) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> accountUids = prefs.getStringList('account_uids') ?? [];
    if (!accountUids.contains(user.uid)) {
      accountUids.add(user.uid);
      await prefs.setStringList('account_uids', accountUids);
      print('AccountLoginScreen: Added UID ${user.uid} to SharedPreferences');
    }
    await prefs.setString('account_${user.uid}_email', user.email ?? '');
    await prefs.setString('account_${user.uid}_password', _passwordController.text);
    await _saveDeviceInfo(user.uid);
    await _navigateAfterLogin(user);
    if (mounted) setState(() => _isLoading = false);
  }

  String _getFriendlyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    print('AccountLoginScreen: Building UI');
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
                    const Text(
                      'Add New Account',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
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
                    CustomTextField(
                      controller: _emailController,
                      labelText: 'Email',
                      fillColor: Colors.white24,
                      textColor: Colors.white,
                      keyboardType: TextInputType.emailAddress,
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
                    const SizedBox(height: 25),
                    GradientButton(
                      text: 'Login',
                      onPressed: _handleEmailLogin,
                      isLoading: _isLoading,
                      gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0183FB))),
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