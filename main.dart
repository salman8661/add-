import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/account_login_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/phone_setup_screen.dart';
import 'screens/update_screen.dart'; // For AccountInfoScreen
import 'screens/forgot_password_screen.dart'; // Newly added
import 'providers/auth_provider.dart' as customAuth;
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Set Firebase Auth persistence to LOCAL for session persistence
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug, // Debug mode for testing
      // androidProvider: AndroidProvider.playIntegrity, // Uncomment for production
    );
    print('main.dart: Firebase initialized successfully');
  } catch (e) {
    print('main.dart: Error initializing Firebase: $e');
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => customAuth.CustomAuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        // Fallback theme if themeProvider.themeData is null
        final theme = themeProvider.themeData ?? ThemeData.dark(); // Changed to dark for consistency
        return MaterialApp(
          title: 'DoDay Messenger',
          theme: theme,
          home: const SplashScreen(), // Always start with SplashScreen
          onGenerateRoute: (settings) {
            final routeName = settings.name ?? '/';
            print('main.dart: Navigating to route: "$routeName" with arguments: ${settings.arguments}');

            // Handle root or invalid route
            if (routeName == '/' || routeName.isEmpty) {
              print('main.dart: Root or empty route, routing to SplashScreen');
              return MaterialPageRoute(builder: (context) => const SplashScreen());
            }

            // Parse URI safely
            Uri uri;
            try {
              uri = Uri.parse(routeName);
            } catch (e) {
              print('main.dart: Error parsing route "$routeName": $e, defaulting to SplashScreen');
              return MaterialPageRoute(builder: (context) => const SplashScreen());
            }

            if (uri.pathSegments.isEmpty) {
              print('main.dart: No path segments, defaulting to SplashScreen');
              return MaterialPageRoute(builder: (context) => const SplashScreen());
            }

            final path = uri.pathSegments[0];
            switch (path) {
              case 'login':
                print('main.dart: Routing to LoginScreen');
                return MaterialPageRoute(builder: (context) => const LoginScreen());
              case 'otp-verification':
                final args = settings.arguments as Map<String, dynamic>?;
                final phoneNumber = args?['phoneNumber'] as String?;
                final verificationId = args?['verificationId'] as String?;
                final isReset = args?['isReset'] as bool? ?? false;
                if (phoneNumber == null || verificationId == null) {
                  print('main.dart: Invalid OTP args (phoneNumber or verificationId missing), redirecting to LoginScreen');
                  return MaterialPageRoute(builder: (context) => const LoginScreen());
                }
                print('main.dart: Routing to OTPVerificationScreen with phoneNumber: $phoneNumber, verificationId: $verificationId, isReset: $isReset');
                return MaterialPageRoute(
                  builder: (context) => OTPVerificationScreen(
                    phoneNumber: phoneNumber,
                    verificationId: verificationId,
                    isReset: isReset,
                  ),
                );
              case 'profile-setup':
                print('main.dart: Routing to ProfileSetupScreen');
                return MaterialPageRoute(builder: (context) => const ProfileSetupScreen());
              case 'home':
                print('main.dart: Routing to HomeScreen');
                return MaterialPageRoute(builder: (context) => const HomeScreen());
              case 'edit-profile':
                print('main.dart: Routing to EditProfileScreen');
                return MaterialPageRoute(builder: (context) => const EditProfileScreen());
              case 'settings':
                print('main.dart: Routing to SettingsScreen');
                return MaterialPageRoute(builder: (context) => const SettingsScreen());
              case 'terms':
                print('main.dart: Routing to TermsScreen');
                return MaterialPageRoute(builder: (context) => const TermsScreen());
              case 'account-login':
                print('main.dart: Routing to AccountLoginScreen');
                return MaterialPageRoute(builder: (context) => const AccountLoginScreen());
              case 'email-verification':
                print('main.dart: Routing to EmailVerificationScreen');
                return MaterialPageRoute(builder: (context) => const EmailVerificationScreen());
              case 'phone-setup':
                print('main.dart: Routing to PhoneSetupScreen');
                return MaterialPageRoute(builder: (context) => const PhoneSetupScreen());
              case 'account-info':
                print('main.dart: Routing to AccountInfoScreen');
                return MaterialPageRoute(builder: (context) => const AccountInfoScreen());
              case 'forgot-password':
                print('main.dart: Routing to ForgotPasswordScreen');
                return MaterialPageRoute(builder: (context) => const ForgotPasswordScreen());
              default:
                print('main.dart: Unknown route "$path", defaulting to SplashScreen');
                return MaterialPageRoute(builder: (context) => const SplashScreen());
            }
          },
        );
      },
    );
  }
}