import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../providers/auth_provider.dart' as customAuth;
import '../providers/theme_provider.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/update_screen.dart';
import '../widgets/custom_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String? _profileImageUrl;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  int _unreadNotifications = 0;
  Map<String, dynamic>? _accountInfo;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadNotifications();
    _loadAccountInfo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          setState(() => _profileImageUrl = doc.data()!['profileImageUrl'] as String?);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  Future<void> _loadNotifications() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('recipientId', isEqualTo: user.uid)
            .where('read', isEqualTo: false)
            .get();
        setState(() => _unreadNotifications = querySnapshot.docs.length);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading notifications: $e')));
      }
    }
  }

  Future<void> _loadAccountInfo() async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        setState(() {
          _accountInfo = {
            'phoneNumber': doc.data()?['phoneNumber'] ?? user.phoneNumber ?? 'Not set',
            'email': doc.data()?['email'] ?? user.email ?? 'Not set',
            'password': doc.data()?['password'] ?? 'Not set', // Added password field
          };
        });
      } catch (e) {
        setState(() {
          _accountInfo = {
            'phoneNumber': user.phoneNumber ?? 'Not set',
            'email': user.email ?? 'Not set',
            'password': 'Not set',
          };
        });
      }
    }
  }

  Future<bool> _showLogoutConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context, false)),
          TextButton(child: const Text('Logout', style: TextStyle(color: Colors.red)), onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    ) ?? false;
  }

  void _showProfileOptions() {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Edit Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.blue),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.blue),
            title: const Text('Account Management'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/account-info');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              if (await _showLogoutConfirmation()) {
                await authProvider.signOut();
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/login');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _searchQuery = query.trim());
    });
  }

  Future<bool> _isFriendRequestSent(String targetUserId) async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return false;

    final querySnapshot = await FirebaseFirestore.instance
        .collection('friend_requests')
        .where('senderId', isEqualTo: user.uid)
        .where('recipientId', isEqualTo: targetUserId)
        .where('status', isEqualTo: 'pending')
        .get();
    return querySnapshot.docs.isNotEmpty;
  }

  Future<void> _manageFriendRequest(String targetUserId, bool isSent) async {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return;

    try {
      if (!isSent) {
        await FirebaseFirestore.instance.collection('friend_requests').add({
          'senderId': user.uid,
          'recipientId': targetUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('notifications').add({
          'recipientId': targetUserId,
          'type': 'friend_request',
          'senderId': user.uid,
          'message': '${user.displayName ?? 'A user'} sent you a friend request',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('friend_requests')
            .where('senderId', isEqualTo: user.uid)
            .where('recipientId', isEqualTo: targetUserId)
            .where('status', isEqualTo: 'pending')
            .get();
        for (var doc in querySnapshot.docs) {
          await doc.reference.delete();
        }
      }
      _loadNotifications();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildSearchResults() {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) return const Center(child: Text('Please log in to search users'));

    if (_searchQuery.isEmpty) return const Center(child: Text('Enter a username to search'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: _searchQuery)
          .where('username', isLessThanOrEqualTo: '$_searchQuery\uf8ff')
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final users = snapshot.data?.docs ?? [];
        if (users.isEmpty) return const Center(child: Text('No users found'));

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userData = users[index].data() as Map<String, dynamic>;
            final targetUserId = users[index].id;
            return FutureBuilder<bool>(
              future: _isFriendRequestSent(targetUserId),
              builder: (context, friendSnapshot) {
                if (friendSnapshot.connectionState == ConnectionState.waiting) return const ListTile(title: Text('Loading...'));
                final isSent = friendSnapshot.data ?? false;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundImage: userData['profileImageUrl'] != null ? CachedNetworkImageProvider(userData['profileImageUrl']) : null,
                    child: userData['profileImageUrl'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(userData['username'] ?? 'Unknown User'),
                  subtitle: Text(userData['name'] ?? ''),
                  trailing: ElevatedButton(
                    onPressed: () => _manageFriendRequest(targetUserId, isSent),
                    child: Text(isSent ? 'Remove' : 'Add'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return WillPopScope(
      onWillPop: () async {
        SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          title: const Text('DoDay Messenger', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.notifications),
                  if (_unreadNotifications > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                        child: Text(_unreadNotifications.toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
              onPressed: () {},
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _showProfileOptions,
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
                  child: _profileImageUrl == null ? const Icon(Icons.person) : null,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_selectedIndex == 1) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: CustomTextField(
                  controller: _searchController,
                  labelText: 'Search usernames...',
                  onChanged: _onSearchChanged,
                ),
              ),
              Expanded(child: _buildSearchResults()),
            ] else ...[
              Container(
                height: 100,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('stories').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) return Center(child: Text('Error loading stories', style: theme.textTheme.bodyMedium));
                    final stories = snapshot.data!.docs;
                    if (stories.isEmpty) return Center(child: Text('No stories yet', style: theme.textTheme.bodyMedium));
                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: stories.length,
                      itemBuilder: (context, index) {
                        final story = stories[index].data() as Map<String, dynamic>;
                        return _buildStoryCircle(story);
                      },
                    );
                  },
                ),
              ),
              Expanded(child: _buildContent()),
            ],
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() {
            _selectedIndex = index;
            if (index == 1) _searchController.clear();
          }),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
            BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Reels'),
            BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Calls'),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryCircle(Map<String, dynamic> story) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: story['profileImageUrl'] != null ? CachedNetworkImageProvider(story['profileImageUrl']) : null,
            child: story['profileImageUrl'] == null ? const Icon(Icons.person) : null,
          ),
          const SizedBox(height: 4),
          Text(story['username'] ?? 'User'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    switch (_selectedIndex) {
      case 0:
        return const Center(child: Text('Chats Coming Soon'));
      case 2:
        return const Center(child: Text('Add Feature Coming Soon'));
      case 3:
        return const Center(child: Text('Reels Coming Soon'));
      case 4:
        return const Center(child: Text('Calls Coming Soon'));
      default:
        return Container();
    }
  }
}