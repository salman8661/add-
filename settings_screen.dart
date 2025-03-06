import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: Image.asset(
            'assets/back.png', // Use back.png for back button
            width: 24, // Adjust width as needed
            height: 24, // Adjust height as needed
            color: themeProvider.themeData.appBarTheme.foregroundColor, // Match app bar text/icon color
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.arrow_back, // Fallback icon if back.png is missing
              color: themeProvider.themeData.appBarTheme.foregroundColor,
            ),
          ),
          onPressed: () => Navigator.pop(context), // Navigate back to previous screen
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Dark Mode'),
              trailing: Switch(
                value: themeProvider.isDarkMode,
                onChanged: (value) {
                  themeProvider.toggleTheme();
                },
                activeColor: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}