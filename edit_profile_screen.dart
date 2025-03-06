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

    return TextEditingValue(
      text: newText.toString(),
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _usernameController = TextEditingController();
  final _nameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  String? _selectedGender = 'Prefer not to say';
  bool _isLoading = false;
  String? _errorMessage;
  File? _profileImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    print('EditProfileScreen: Initializing');
    _fetchUserProfile();
    _usernameController.addListener(() {
      if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
    });
  }

  @override
  void dispose() {
    print('EditProfileScreen: Disposing');
    _usernameController.dispose();
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
        if (mounted) {
          setState(() {
            _usernameController.text = data['username'] ?? '';
            _nameController.text = data['name'] ?? '';
            _dateOfBirthController.text = data['dateOfBirth'] ?? '';
            _selectedGender = data['gender'] ?? 'Prefer not to say';
            _profileImageUrl = data['profileImageUrl'];
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to load profile: $e');
    }
  }

  Future<bool> _isUsernameUnique(String username, String currentUserId) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();
    return query.docs.isEmpty || query.docs.every((doc) => doc.id == currentUserId);
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
            leading: Image.asset('assets/camera.png', width: 24, height: 24, color: themeProvider.themeData.textTheme.bodyLarge!.color),
            title: Text('Camera', style: themeProvider.themeData.textTheme.bodyLarge),
            onTap: () {
              Navigator.pop(context);
              _selectImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Image.asset('assets/gallery.png', width: 24, height: 24, color: themeProvider.themeData.textTheme.bodyLarge!.color),
            title: Text('Gallery', style: themeProvider.themeData.textTheme.bodyLarge),
            onTap: () {
              Navigator.pop(context);
              _selectImage(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfileChanges() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final name = _nameController.text.trim();
    final dateOfBirth = _dateOfBirthController.text.trim();

    if (username.isEmpty) {
      if (mounted) setState(() {
        _errorMessage = 'Username is required.';
        _isLoading = false;
      });
      return;
    }

    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user == null) {
      if (mounted) setState(() {
        _errorMessage = 'Authentication error.';
        _isLoading = false;
      });
      return;
    }

    final isUnique = await _isUsernameUnique(username, user.uid);
    if (!isUnique) {
      if (mounted) setState(() {
        _errorMessage = 'Username is already taken.';
        _isLoading = false;
      });
      return;
    }

    try {
      final userData = {
        'username': username,
        'name': name.isEmpty ? null : name,
        'status': 'Hey there!',
        'dateOfBirth': dateOfBirth.isEmpty ? null : dateOfBirth,
        'gender': _selectedGender,
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

      if (mounted) setState(() => _isLoading = false);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() {
        _errorMessage = 'Failed to save profile changes: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    print('EditProfileScreen: Building UI');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: theme.appBarTheme.elevation,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF0183FB), Color(0xFF7C02FB)]).createShader(bounds),
          child: const Text('Edit Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        leading: IconButton(
          icon: Image.asset('assets/back.png', width: 24, height: 24, color: theme.appBarTheme.foregroundColor, errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.30,
              decoration: BoxDecoration(color: theme.cardColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40))),
              child: Center(
                child: GestureDetector(
                  onTap: _showImagePickerModal,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _profileImage != null ? FileImage(_profileImage!) : _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : const AssetImage('assets/profile_default.png') as ImageProvider,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Image.asset('assets/camera.png', width: 28, height: 28, color: theme.textTheme.bodyLarge!.color),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CustomTextField(
                      controller: _usernameController,
                      labelText: 'Username (unique)',
                      fillColor: theme.cardColor,
                      textColor: theme.textTheme.bodyLarge!.color,
                      keyboardType: TextInputType.text,
                      errorText: _errorMessage,
                      borderRadius: 12,
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      controller: _nameController,
                      labelText: 'Name',
                      fillColor: theme.cardColor,
                      textColor: theme.textTheme.bodyLarge!.color,
                      keyboardType: TextInputType.text,
                      borderRadius: 12,
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      controller: _dateOfBirthController,
                      labelText: 'Date of Birth (DD/MM/YYYY)',
                      fillColor: theme.cardColor,
                      textColor: theme.textTheme.bodyLarge!.color,
                      keyboardType: TextInputType.number,
                      borderRadius: 12,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, DateInputFormatter()],
                      maxLength: 10,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
                      child: DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: InputBorder.none,
                          labelText: 'Gender',
                          labelStyle: theme.textTheme.bodyMedium!.copyWith(fontSize: 16),
                        ),
                        dropdownColor: theme.scaffoldBackgroundColor,
                        style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                        icon: Image.asset('assets/dropdown.png', width: 24, height: 24, color: theme.textTheme.bodyLarge!.color, errorBuilder: (_, __, ___) => const Icon(Icons.arrow_drop_down_circle)),
                        items: ['Male', 'Female', 'Prefer not to say'].map((gender) => DropdownMenuItem(value: gender, child: Text(gender))).toList(),
                        onChanged: (newValue) => setState(() => _selectedGender = newValue ?? 'Prefer not to say'),
                        borderRadius: BorderRadius.circular(12),
                        isExpanded: true,
                      ),
                    ),
                    const SizedBox(height: 25),
                    GradientButton(
                      text: 'Save Changes',
                      onPressed: _saveProfileChanges,
                      isLoading: _isLoading,
                      gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    ),
                    if (_errorMessage != null && !_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(_errorMessage!, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
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