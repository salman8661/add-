import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as customAuth;
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class PhoneSetupScreen extends StatefulWidget {
  const PhoneSetupScreen({super.key});

  @override
  State<PhoneSetupScreen> createState() => _PhoneSetupScreenState();
}

class _PhoneSetupScreenState extends State<PhoneSetupScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final phoneNumber = _phoneController.text.trim();
    if (!_isValidPhoneNumber(phoneNumber)) {
      if (mounted) setState(() {
        _errorMessage = 'Please enter a valid phone number';
        _isLoading = false;
      });
      return;
    }

    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    try {
      await authProvider.sendOTP(phoneNumber);
      final verificationId = authProvider.verificationId;
      if (verificationId == null) throw Exception('Verification ID not set');
      if (mounted) {
        Navigator.pushNamed(context, '/otp-verification', arguments: {
          'phoneNumber': phoneNumber,
          'verificationId': verificationId,
          'isReset': false,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error sending OTP: $e';
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorMessage!)));
      }
    }
  }

  bool _isValidPhoneNumber(String input) => RegExp(r'^\+[0-9]{10,15}$').hasMatch(input);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Set Up Phone'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CustomTextField(
              controller: _phoneController,
              labelText: 'Phone Number (e.g., +1234567890)',
              fillColor: theme.cardColor,
              textColor: theme.textTheme.bodyLarge!.color,
              keyboardType: TextInputType.phone,
              errorText: _errorMessage,
              borderRadius: 12,
            ),
            const SizedBox(height: 20),
            GradientButton(
              text: 'Send OTP',
              onPressed: _sendOTP,
              isLoading: _isLoading,
              gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/profile-setup'),
              child: Text('Skip', style: theme.textTheme.bodyMedium!.copyWith(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }
}