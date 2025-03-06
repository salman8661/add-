import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart' as customAuth;

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<customAuth.CustomAuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
      ),
      body: Center(
        child: Text(
          'Contacts Screen Content',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
