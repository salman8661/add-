import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll('/', '');
    if (text.length > 8) text = text.substring(0, 8);
    StringBuffer newText = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 2 || i == 4) newText.write('/');
      newText.write(text[i]);
    }
    return TextEditingValue(text: newText.toString(), selection: TextSelection.collapsed(offset: newText.length));
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  String _selectedGender = 'Prefer not to say';
  bool _isLoading = false;
  String? _errorMessage;
  File? _profileImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _dateOfBirthController.text = data['dateOfBirth'] ?? '';
          _selected {super.key}selectedGender = data['gender'] ?? 'Prefer not to say';
          _profileImageUrl = data['profileImageUrl'];
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load profile: $e');
    }
  }

  Future<void> _selectImage(ImageSource source) async {
    try {
      final pickedImage = await ImagePicker().pickImage(source: source);
      if (pickedImage != null && mounted) {
        setState(() => _profileImage = File(pickedImage.path));
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Image selection failed: $e');
    }
  }

  void _showImagePickerModal() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: themeProvider.isDarkMode ? Colors.black : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.blue),
            title: const Text('Camera'),
            onTap: () {
              Navigator.pop(context);
              _selectImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.blue),
            title: const Text('Gallery'),
            onTap: () {
              Navigator.pop(context);
              _selectImage(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfileData() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'User not authenticated';
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists || doc.data()?['username'] == null) {
        setState(() {
          _errorMessage = 'Username not set. Please sign up again.';
          _isLoading = false;
        });
        return;
      }

      final userData = {
        'name': _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        'dateOfBirth': _dateOfBirthController.text.trim().isEmpty ? null : _dateOfBirthController.text.trim(),
        'gender': _selectedGender,
        'status': 'Hey there!',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));

      if (_profileImage != null) {
        final storageRef = FirebaseStorage.instance.ref().child('profile_images/${user.uid}/profile.jpg');
        await storageRef.putFile(_profileImage!);
        final imageUrl = await storageRef.getDownloadURL();
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'profileImageUrl': imageUrl});
        if (mounted) setState(() => _profileImageUrl = imageUrl);
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) setState(() {
        _errorMessage = 'Failed to save profile: $e';
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
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        title: const Text('Profile Setup', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
            await authProvider.signOut();
            if (mounted) Navigator.pushReplacementNamed(context, '/login');
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.30,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
              ),
              child: Center(
                child: GestureDetector(
                  onTap: _showImagePickerModal,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : _profileImageUrl != null
                            ? NetworkImage(_profileImageUrl!)
                            : const AssetImage('assets/profile_default.png') as ImageProvider,
                      ),
                      const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.camera_alt, color: Colors.blue, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                child: Column(
                  children: [
                    CustomTextField(
                      controller: _nameController,
                      labelText: 'Name',
                      fillColor: theme.cardColor,
                      textColor: theme.textTheme.bodyLarge!.color,
                      borderRadius: 12,
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      controller: _dateOfBirthController,
                      labelText: 'Date of Birth (DD/MM/YYYY)',
                      fillColor: theme.cardColor,
                      textColor: theme.textTheme.bodyLarge!.color,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, DateInputFormatter()],
                      maxLength: 10,
                      borderRadius: 12,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      decoration: InputDecoration(
                        fillColor: theme.cardColor,
                        filled: true,
                        labelText: 'Gender',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: ['Male', 'Female', 'Prefer not to say']
                          .map((gender) => DropdownMenuItem(value: gender, child: Text(gender)))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedGender = value ?? 'Prefer not to say'),
                    ),
                    const SizedBox(height: 25),
                    GradientButton(
                      text: 'Save Profile',
                      onPressed: _saveProfileData,
                      isLoading: _isLoading,
                      gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    ),
                    if (_errorMessage != null && !_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
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