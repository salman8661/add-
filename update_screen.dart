import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/gradient_button.dart';

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  _AccountInfoScreenState createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  String? _phoneNumber;
  String? _email;
  String? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          setState(() {
            _phoneNumber = doc.data()!['phoneNumber'] as String? ?? user.phoneNumber ?? 'Not set';
            _email = doc.data()!['email'] as String? ?? user.email ?? 'Not set';
            _dateOfBirth = doc.data()!['dateOfBirth'] as String? ?? 'Not set';
          });
        } else {
          setState(() {
            _phoneNumber = user.phoneNumber ?? 'Not set';
            _email = user.email ?? 'Not set';
            _dateOfBirth = 'Not set';
          });
        }
      } catch (e) {
        print('AccountInfoScreen: Error fetching user data: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
      }
    }
  }

  Future<List<Map<String, String>>> _getStoredAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountList = prefs.getStringList('account_uids') ?? [];
    final accounts = <Map<String, String>>[];
    for (var uid in accountList) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data()!;
          final username = userData['username'] as String? ?? 'Unknown';
          final name = userData['name'] as String? ?? 'No Name Set';
          final profileImageUrl = userData['profileImageUrl'] as String? ?? '';
          accounts.add({
            'uid': uid,
            'username': username,
            'name': name,
            'profileImageUrl': profileImageUrl,
          });
        }
      } catch (e) {
        print('AccountInfoScreen: Error fetching account $uid: $e');
      }
    }
    return accounts;
  }

  Future<void> _switchAccount(String uid, String username) async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('account_${uid}_email') ?? '';
      final password = prefs.getString('account_${uid}_password') ?? '';

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Credentials not found for $username');
      }

      if (authProvider.currentUser != null) await authProvider.signOut();
      await authProvider.signInWithEmailAndPassword(email, password); // Saves password to Firestore
      final user = authProvider.currentUser;

      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!user.emailVerified) {
          await user.sendEmailVerification();
          Navigator.pushReplacementNamed(context, '/email-verification');
        } else if (doc.exists && doc.data()?['username'] != null) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacementNamed(context, '/profile-setup');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to switch account: $e')));
    }
  }

  Future<void> _authStateStabilize(customAuth.CustomAuthProvider authProvider) async {
    const maxAttempts = 15;
    var attempts = 0;
    while (authProvider.currentUser == null && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
    if (authProvider.currentUser == null) {
      throw Exception('Authentication did not stabilize after $maxAttempts attempts');
    }
  }

  void _showAddAccountBottomSheet(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: themeProvider.themeData.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return FutureBuilder<List<Map<String, String>>>(
          future: _getStoredAccounts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No accounts added yet.'),
                    const Divider(),
                    _buildAddAnotherAccountTile(context),
                  ],
                ),
              );
            }

            final accounts = snapshot.data!;
            final currentAccountIndex = accounts.indexWhere((account) => account['uid'] == currentUser?.uid);
            if (currentAccountIndex != -1) {
              final currentAccount = accounts.removeAt(currentAccountIndex);
              accounts.insert(0, currentAccount);
            }

            return ListView(
              shrinkWrap: true,
              children: [
                ...accounts.map((account) {
                  final uid = account['uid']!;
                  final username = account['username']!;
                  final name = account['name']!;
                  final profileImageUrl = account['profileImageUrl']!;
                  final isCurrent = currentUser != null && currentUser.uid == uid;

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundImage: profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : const AssetImage('assets/default_profile.png') as ImageProvider,
                    ),
                    title: Text(username, style: themeProvider.themeData.textTheme.bodyLarge),
                    subtitle: Text(name, style: themeProvider.themeData.textTheme.bodySmall),
                    trailing: isCurrent
                        ? ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Image.asset(
                        'assets/check.png',
                        width: 24,
                        height: 24,
                        color: Colors.white,
                      ),
                    )
                        : null,
                    onTap: isCurrent ? null : () => _switchAccount(uid, username),
                  );
                }).toList(),
                const Divider(),
                _buildAddAnotherAccountTile(context),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAddAnotherAccountTile(BuildContext context) {
    return ListTile(
      leading: Image.asset(
        'assets/add-more.png',
        width: 24,
        height: 24,
        color: Colors.blue,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.add, color: Colors.blue, size: 24),
      ),
      title: const Text(
        'Add Another Account',
        style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold),
      ),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/account-login');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final needsUpdate = _phoneNumber == 'Not set' || _email == 'Not set';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Account Info',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Image.asset(
                'assets/personal-info.png',
                width: 24,
                height: 24,
                color: Colors.blue,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.blue, size: 24),
              ),
              title: Text('Personal Information', style: theme.textTheme.bodyLarge),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (needsUpdate)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GradientButton(
                        text: 'Update',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => UpdateScreen()),
                          ).then((_) => _fetchUserData());
                        },
                        gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                        borderRadius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  Image.asset(
                    'assets/right-arrow.png',
                    width: 24,
                    height: 24,
                    color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.arrow_forward,
                      color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                      size: 24,
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UpdateScreen()),
                ).then((_) => _fetchUserData());
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Image.asset(
                'assets/session.png',
                width: 24,
                height: 24,
                color: Colors.blue,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.devices, color: Colors.blue, size: 24),
              ),
              title: Text('Session Management', style: theme.textTheme.bodyLarge),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SessionManagementScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Image.asset(
                'assets/add-account.png',
                width: 24,
                height: 24,
                color: Colors.blue,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_circle, color: Colors.blue, size: 24),
              ),
              title: Text('Add Account', style: theme.textTheme.bodyLarge),
              trailing: SizedBox(
                width: 45,
                child: GestureDetector(
                  onTap: () => _showAddAccountBottomSheet(context),
                  child: const Text(
                    'Add',
                    style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SessionManagementScreen extends StatefulWidget {
  const SessionManagementScreen({super.key});

  @override
  _SessionManagementScreenState createState() => _SessionManagementScreenState();
}

class _SessionManagementScreenState extends State<SessionManagementScreen> {
  late String _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _getCurrentDeviceId();
  }

  Future<void> _getCurrentDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _currentDeviceId = androidInfo.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _currentDeviceId = iosInfo.identifierForVendor ?? DateTime.now().millisecondsSinceEpoch.toString();
    } else {
      _currentDeviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }
    setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetchLoggedSessions() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return [];

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .get();
    return querySnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'deviceName': data['deviceName'] as String? ?? 'Unknown',
        'ip': data['ip'] as String? ?? 'Unknown',
        'location': data['location'] as String? ?? 'Unknown',
        'timestamp': data['timestamp'] as Timestamp? ?? Timestamp.now(),
        'deviceId': doc.id,
      };
    }).toList();
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final sessionTime = timestamp.toDate();
    final difference = now.difference(sessionTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    return '${difference.inDays} days ago';
  }

  Future<bool> _showLogoutConfirmation(String deviceName) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.themeData.cardColor,
        title: Text('Confirm Logout of "$deviceName"?', style: themeProvider.themeData.textTheme.headlineMedium),
        content: Text(
          'You will lose saved credentials on this device and remove access to the account. Are you sure?',
          style: themeProvider.themeData.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.blue)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text('Logout', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _logoutSession(String deviceId, String deviceName) async {
    if (!(await _showLogoutConfirmation(deviceName))) return;

    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId)
          .delete();
      if (deviceId == _currentDeviceId) {
        await authProvider.signOut();
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        setState(() {});
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Session logged out successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error logging out session: $e')));
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
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Logged Sessions',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchLoggedSessions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: theme.textTheme.bodyMedium));
            }
            final sessions = snapshot.data ?? [];
            if (sessions.isEmpty) {
              return Center(child: Text('No logged sessions found.', style: theme.textTheme.bodyMedium));
            }

            return ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final deviceName = session['deviceName'] as String;
                final ip = session['ip'] as String;
                final location = session['location'] as String;
                final timestamp = session['timestamp'] as Timestamp;
                final deviceId = session['deviceId'] as String;
                final timeAgo = _formatTimestamp(timestamp);
                final isCurrentSession = deviceId == _currentDeviceId;
                final isAndroid = deviceName.toLowerCase().contains('android') || Platform.isAndroid;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    border: Border.all(color: Colors.purple.shade200, width: 1),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset(
                          isAndroid ? 'assets/android.png' : 'assets/ios_device.png',
                          width: 36,
                          height: 36,
                          color: theme.textTheme.bodyLarge!.color,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.device_hub,
                            color: theme.textTheme.bodyLarge!.color,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    deviceName,
                                    style: theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                  if (isCurrentSession) ...[
                                    const SizedBox(width: 8),
                                    Image.asset(
                                      'assets/greendot.png',
                                      width: 12,
                                      height: 12,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text('IP: $ip', style: theme.textTheme.bodySmall!.copyWith(fontSize: 14)),
                              Text('Location: $location', style: theme.textTheme.bodySmall!.copyWith(fontSize: 14)),
                              Text('Logged: $timeAgo', style: theme.textTheme.bodySmall!.copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Image.asset(
                            'assets/minus.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.remove_circle, color: Colors.red, size: 24),
                          ),
                          onPressed: () => _logoutSession(deviceId, deviceName),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  _UpdateScreenState createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  String? _phoneNumber;
  String? _email;
  String? _dateOfBirth;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() => _isLoading = true);
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          setState(() {
            _phoneNumber = doc.data()!['phoneNumber'] as String? ?? user.phoneNumber ?? 'Not set';
            _email = doc.data()!['email'] as String? ?? user.email ?? 'Not set';
            _dateOfBirth = doc.data()!['dateOfBirth'] as String? ?? 'Not set';
          });
        } else {
          setState(() {
            _phoneNumber = user.phoneNumber ?? 'Not set';
            _email = user.email ?? 'Not set';
            _dateOfBirth = 'Not set';
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error refreshing data: $e')));
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;
    final hasPhone = _phoneNumber != 'Not set' && _phoneNumber != null;
    final hasEmail = _email != 'Not set' && _email != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Personal Info',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchUserData,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update your personal information below.',
                  style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Image.asset(
                    'assets/phone.png',
                    width: 24,
                    height: 24,
                    color: Colors.blue,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.phone, color: Colors.blue, size: 24),
                  ),
                  title: Text(
                    hasPhone ? 'Phone Number: $_phoneNumber' : 'Update Phone Number',
                    style: theme.textTheme.bodyLarge,
                  ),
                  subtitle: !hasPhone
                      ? Text(
                    'You can also login with this phone number using OTP',
                    style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
                  )
                      : null,
                  trailing: GradientButton(
                    text: hasPhone ? 'Change' : 'Update',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => PhoneUpdateScreen()),
                      ).then((_) => _fetchUserData());
                    },
                    gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Image.asset(
                    'assets/email.png',
                    width: 24,
                    height: 24,
                    color: Colors.blue,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.email, color: Colors.blue, size: 24),
                  ),
                  title: Text(
                    hasEmail ? 'Email: $_email' : 'Update Email',
                    style: theme.textTheme.bodyLarge,
                  ),
                  subtitle: !hasEmail
                      ? Text(
                    'Set an email to log in if you don’t have your phone number.',
                    style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
                  )
                      : null,
                  trailing: GradientButton(
                    text: hasEmail ? 'Change' : 'Update',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => EmailUpdateScreen(hasEmail: hasEmail)),
                      ).then((_) => _fetchUserData());
                    },
                    gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
                if (hasEmail)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Image.asset(
                      'assets/changepass.png',
                      width: 24,
                      height: 24,
                      color: Colors.blue,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.lock, color: Colors.blue, size: 24),
                    ),
                    title: Text('Change Password', style: theme.textTheme.bodyLarge),
                    trailing: GradientButton(
                      text: 'Change',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PasswordUpdateScreen()),
                        ).then((_) => _fetchUserData());
                      },
                      gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                      borderRadius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                if (hasEmail) const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Image.asset(
                    'assets/birth.png',
                    width: 24,
                    height: 24,
                    color: Colors.blue,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.cake, color: Colors.blue, size: 24),
                  ),
                  title: Text(
                    _dateOfBirth != 'Not set' ? 'Date of Birth: $_dateOfBirth' : 'Set Date of Birth',
                    style: theme.textTheme.bodyLarge,
                  ),
                  trailing: GradientButton(
                    text: 'Change',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => DateOfBirthUpdateScreen()),
                      ).then((_) => _fetchUserData());
                    },
                    gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

class EmailUpdateScreen extends StatefulWidget {
  final bool hasEmail;

  const EmailUpdateScreen({this.hasEmail = false, super.key});

  @override
  _EmailUpdateScreenState createState() => _EmailUpdateScreenState();
}

class _EmailUpdateScreenState extends State<EmailUpdateScreen> {
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  bool _isCurrentPasswordObscured = true;
  bool _isNewPasswordObscured = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Change Email',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.hasEmail
                    ? 'Enter your current password, new email, and new password to change your email.'
                    : 'Set an email and password for your account.',
                style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (widget.hasEmail)
                CustomTextField(
                  controller: _currentPasswordController,
                  labelText: 'Current Password',
                  fillColor: theme.cardColor.withOpacity(0.8),
                  textColor: theme.textTheme.bodyLarge!.color,
                  obscureText: _isCurrentPasswordObscured,
                  borderRadius: 12,
                  suffixIcon: IconButton(
                    icon: Image.asset(
                      _isCurrentPasswordObscured ? 'assets/hide.png' : 'assets/unhide.png',
                      width: 24,
                      height: 24,
                      color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                      errorBuilder: (context, error, stackTrace) => Icon(
                        _isCurrentPasswordObscured ? Icons.visibility_off : Icons.visibility,
                        color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                      ),
                    ),
                    onPressed: () => setState(() => _isCurrentPasswordObscured = !_isCurrentPasswordObscured),
                  ),
                ),
              if (widget.hasEmail) const SizedBox(height: 12),
              CustomTextField(
                controller: _newEmailController,
                labelText: 'New Email',
                fillColor: theme.cardColor.withOpacity(0.8),
                textColor: theme.textTheme.bodyLarge!.color,
                keyboardType: TextInputType.emailAddress,
                borderRadius: 12,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _newPasswordController,
                labelText: 'New Password',
                fillColor: theme.cardColor.withOpacity(0.8),
                textColor: theme.textTheme.bodyLarge!.color,
                obscureText: _isNewPasswordObscured,
                borderRadius: 12,
                suffixIcon: IconButton(
                  icon: Image.asset(
                    _isNewPasswordObscured ? 'assets/hide.png' : 'assets/unhide.png',
                    width: 24,
                    height: 24,
                    color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                    errorBuilder: (context, error, stackTrace) => Icon(
                      _isNewPasswordObscured ? Icons.visibility_off : Icons.visibility,
                      color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                    ),
                  ),
                  onPressed: () => setState(() => _isNewPasswordObscured = !_isNewPasswordObscured),
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: widget.hasEmail ? 'Change' : 'Update',
                onPressed: () async {
                  final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
                  final user = authProvider.currentUser;
                  if (user == null) return;

                  final currentPassword = _currentPasswordController.text.trim();
                  final newEmail = _newEmailController.text.trim();
                  final newPassword = _newPasswordController.text.trim();

                  if (newEmail.isEmpty || newPassword.isEmpty || (widget.hasEmail && currentPassword.isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields')));
                    return;
                  }

                  if (!_isValidEmail(newEmail)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email')));
                    return;
                  }

                  if (newPassword.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New password must be at least 6 characters')));
                    return;
                  }

                  setState(() => _isLoading = true);

                  try {
                    if (widget.hasEmail) {
                      final credential = EmailAuthProvider.credential(email: user.email!, password: currentPassword);
                      await user.reauthenticateWithCredential(credential);
                      await user.updateEmail(newEmail);
                      await user.updatePassword(newPassword);
                      await user.sendEmailVerification();
                    } else {
                      final credential = EmailAuthProvider.credential(email: newEmail, password: newPassword);
                      await user.linkWithCredential(credential);
                      await user.sendEmailVerification();
                    }

                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                      'email': newEmail,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('account_${user.uid}_email', newEmail);
                    await prefs.setString('account_${user.uid}_password', newPassword);

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email updated. Verify your new email.')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating email: $e')));
                  } finally {
                    setState(() => _isLoading = false);
                  }
                },
                isLoading: _isLoading,
                gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isValidEmail(String input) => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(input);
}

class PhoneUpdateScreen extends StatefulWidget {
  const PhoneUpdateScreen({super.key});

  @override
  _PhoneUpdateScreenState createState() => _PhoneUpdateScreenState();
}

class _PhoneUpdateScreenState extends State<PhoneUpdateScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+1';
  bool _isLoading = false;

  void _showCountryPicker() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country country) {
        setState(() {
          _countryCode = '+${country.phoneCode}';
          _phoneController.text = _countryCode;
          _phoneController.selection = TextSelection.fromPosition(TextPosition(offset: _phoneController.text.length));
        });
      },
      countryListTheme: CountryListThemeData(
        borderRadius: BorderRadius.circular(10),
        backgroundColor: themeProvider.isDarkMode ? Colors.black : Colors.white,
        textStyle: TextStyle(color: themeProvider.themeData.textTheme.bodyLarge!.color),
        inputDecoration: InputDecoration(
          labelText: 'Search country',
          labelStyle: TextStyle(color: themeProvider.themeData.textTheme.bodyMedium!.color, fontSize: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: themeProvider.themeData.cardColor,
        ),
      ),
    );
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
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Change Phone',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your new phone number to change your phone.',
              style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _phoneController,
              labelText: 'New Phone Number',
              fillColor: theme.cardColor.withOpacity(0.8),
              textColor: theme.textTheme.bodyLarge!.color,
              keyboardType: TextInputType.phone,
              borderRadius: 12,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                child: GestureDetector(
                  onTap: _showCountryPicker,
                  child: Text(
                    _countryCode,
                    style: TextStyle(color: theme.textTheme.bodyLarge!.color, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              text: 'Send OTP',
              onPressed: () async {
                final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
                final phoneNumber = _phoneController.text.trim();
                final formattedPhone = phoneNumber.startsWith('+') ? phoneNumber : _countryCode + phoneNumber;
                if (!_isValidPhoneNumber(formattedPhone)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid phone number')));
                  return;
                }

                setState(() => _isLoading = true);
                try {
                  await authProvider.sendOTP(formattedPhone);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UpdateOTPVerificationScreen(phoneNumber: formattedPhone),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending OTP: $e')));
                } finally {
                  setState(() => _isLoading = false);
                }
              },
              isLoading: _isLoading,
              gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ],
        ),
      ),
    );
  }

  bool _isValidPhoneNumber(String input) => RegExp(r'^\+[0-9]{10,15}$').hasMatch(input);
}

class UpdateOTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;

  const UpdateOTPVerificationScreen({required this.phoneNumber, super.key});

  @override
  _UpdateOTPVerificationScreenState createState() => _UpdateOTPVerificationScreenState();
}

class _UpdateOTPVerificationScreenState extends State<UpdateOTPVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 6; i++) {
      _otpControllers[i].addListener(() {
        if (_otpControllers[i].text.length == 1 && i < 5) {
          _focusNodes[i].unfocus();
          FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
        }
        _checkAndVerifyOTP();
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _checkAndVerifyOTP() async {
    final otp = _otpControllers.map((controller) => controller.text).join();
    if (otp.length != 6 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);

    try {
      await authProvider.verifyOTP(otp);
      final user = authProvider.currentUser!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'phoneNumber': widget.phoneNumber,
        'phoneVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Navigator.pop(context);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number changed successfully')));
    } catch (e) {
      setState(() {
        _errorMessage = 'Error verifying OTP: $e';
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
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Verify OTP',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the 6-digit OTP sent to ${widget.phoneNumber}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _otpControllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: TextStyle(color: theme.textTheme.bodyLarge!.color, fontSize: 24),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: theme.cardColor.withOpacity(0.8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty && index > 0) {
                        _focusNodes[index].unfocus();
                        FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                      }
                    },
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            if (_isLoading) const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_errorMessage != null && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(_errorMessage!, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.red), textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}

class PasswordUpdateScreen extends StatefulWidget {
  const PasswordUpdateScreen({super.key});

  @override
  _PasswordUpdateScreenState createState() => _PasswordUpdateScreenState();
}

class _PasswordUpdateScreenState extends State<PasswordUpdateScreen> {
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  bool _isOldPasswordObscured = true;
  bool _isNewPasswordObscured = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Change Password',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your old and new password to change your password.',
              style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _oldPasswordController,
              labelText: 'Old Password',
              fillColor: theme.cardColor.withOpacity(0.8),
              textColor: theme.textTheme.bodyLarge!.color,
              obscureText: _isOldPasswordObscured,
              borderRadius: 12,
              suffixIcon: IconButton(
                icon: Image.asset(
                  _isOldPasswordObscured ? 'assets/hide.png' : 'assets/unhide.png',
                  width: 24,
                  height: 24,
                  color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                  errorBuilder: (context, error, stackTrace) => Icon(
                    _isOldPasswordObscured ? Icons.visibility_off : Icons.visibility,
                    color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                  ),
                ),
                onPressed: () => setState(() => _isOldPasswordObscured = !_isOldPasswordObscured),
              ),
            ),
            const SizedBox(height: 12),
            CustomTextField(
              controller: _newPasswordController,
              labelText: 'New Password',
              fillColor: theme.cardColor.withOpacity(0.8),
              textColor: theme.textTheme.bodyLarge!.color,
              obscureText: _isNewPasswordObscured,
              borderRadius: 12,
              suffixIcon: IconButton(
                icon: Image.asset(
                  _isNewPasswordObscured ? 'assets/hide.png' : 'assets/unhide.png',
                  width: 24,
                  height: 24,
                  color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                  errorBuilder: (context, error, stackTrace) => Icon(
                    _isNewPasswordObscured ? Icons.visibility_off : Icons.visibility,
                    color: theme.textTheme.bodyLarge!.color!.withOpacity(0.7),
                  ),
                ),
                onPressed: () => setState(() => _isNewPasswordObscured = !_isNewPasswordObscured),
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              text: 'Change',
              onPressed: () async {
                final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
                final user = authProvider.currentUser;
                if (user == null) return;

                final oldPassword = _oldPasswordController.text.trim();
                final newPassword = _newPasswordController.text.trim();

                if (oldPassword.isEmpty || newPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter both passwords')));
                  return;
                }
                if (newPassword.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New password must be at least 6 characters')));
                  return;
                }

                setState(() => _isLoading = true);
                try {
                  await authProvider.updatePassword(oldPassword, newPassword, user);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('account_${user.uid}_password', newPassword);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully')));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error changing password: $e')));
                } finally {
                  setState(() => _isLoading = false);
                }
              },
              isLoading: _isLoading,
              gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class DateOfBirthUpdateScreen extends StatefulWidget {
  const DateOfBirthUpdateScreen({super.key});

  @override
  _DateOfBirthUpdateScreenState createState() => _DateOfBirthUpdateScreenState();
}

class _DateOfBirthUpdateScreenState extends State<DateOfBirthUpdateScreen> {
  final TextEditingController _dateOfBirthController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentDateOfBirth();
  }

  Future<void> _fetchCurrentDateOfBirth() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['dateOfBirth'] != null) {
          setState(() {
            _dateOfBirthController.text = doc.data()!['dateOfBirth'];
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading date of birth: $e')));
      }
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
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png',
            width: 24,
            height: 24,
            color: theme.appBarTheme.foregroundColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back,
              color: theme.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF0183FB), Color(0xFF7C02FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Change Date of Birth',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your new date of birth (DD/MM/YYYY).',
              style: theme.textTheme.bodySmall!.copyWith(color: theme.textTheme.bodyMedium!.color),
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _dateOfBirthController,
              labelText: 'Date of Birth (DD/MM/YYYY)',
              fillColor: theme.cardColor.withOpacity(0.8),
              textColor: theme.textTheme.bodyLarge!.color,
              keyboardType: TextInputType.number,
              borderRadius: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, DateInputFormatter()],
              maxLength: 10,
            ),
            const SizedBox(height: 20),
            GradientButton(
              text: 'Change',
              onPressed: () async {
                final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
                final user = authProvider.currentUser;
                if (user == null) return;

                final dateOfBirth = _dateOfBirthController.text.trim();
                if (dateOfBirth.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid date (DD/MM/YYYY)')));
                  return;
                }

                setState(() => _isLoading = true);
                try {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                    'dateOfBirth': dateOfBirth,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Date of birth updated successfully')));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating date of birth: $e')));
                } finally {
                  setState(() => _isLoading = false);
                }
              },
              isLoading: _isLoading,
              gradientColors: const [Color(0xFF0183FB), Color(0xFF7C02FB)],
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ],
        ),
      ),
    );
  }
}

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