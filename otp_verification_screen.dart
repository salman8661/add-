import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final bool isReset;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.isReset,
  });

  @override
  _OTPVerificationScreenState createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _verifyOTPAndResetPassword() async {
    if (_isLoading || !mounted) return;

    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (otp.length != 6) {
      if (mounted) setState(() => _errorMessage = 'Enter a 6-digit OTP');
      return;
    }
    if (widget.isReset && newPassword.length < 6) {
      if (mounted) setState(() => _errorMessage = 'New password must be at least 6 characters');
      return;
    }

    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(verificationId: widget.verificationId, smsCode: otp);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        if (widget.isReset) {
          await user.updatePassword(_newPasswordController.text.trim());
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'phoneNumber': widget.phoneNumber,
            'password': _newPasswordController.text.trim(), // Save new password in plaintext
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully')));
            Navigator.pushReplacementNamed(context, '/login');
          }
        } else {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'phoneNumber': widget.phoneNumber,
            'phoneVerified': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        _errorMessage = 'Error: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Verify OTP'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Enter the OTP sent to ${widget.phoneNumber}${widget.isReset ? ' and your new password' : ''}',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _otpController,
              labelText: 'OTP (6 digits)',
              fillColor: theme.cardColor,
              textColor: theme.textTheme.bodyLarge!.color,
              keyboardType: TextInputType.number,
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
            if (widget.isReset) ...[
              const SizedBox(height: 20),
              CustomTextField(
                controller: _newPasswordController,
                labelText: 'New Password',
                fillColor: theme.cardColor,
                textColor: theme.textTheme.bodyLarge!.color,
                obscureText: true,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              ),
            ],
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Text(_errorMessage!, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.red)),
            const SizedBox(height: 20),
            GradientButton(
              text: widget.isReset ? 'Verify and Reset' : 'Verify',
              onPressed: _verifyOTPAndResetPassword,
              isLoading: _isLoading,
              gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
            ),
          ],
        ),
      ),
    );
  }
}