// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'admin/admin_dashboard.dart';

// make sure this exists at lib/firebase_options.dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseInitialized = false;
  Object? initError;
  StackTrace? initStack;

  try {
    // Use the generated options (works for web, android, ios)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    firebaseInitialized = true;
    debugPrint('✅ Firebase initialized successfully');
  } catch (e, st) {
    initError = e;
    initStack = st;
    debugPrint('❌ Firebase.initializeApp error: $e');
    debugPrint('$st');
    // Continue to run app so we can show an error UI instead of a stuck splash
  }

  runApp(DORApp(
    firebaseInitialized: firebaseInitialized,
    initError: initError,
    initStack: initStack,
  ));
}

class DORApp extends StatelessWidget {
  final bool firebaseInitialized;
  final Object? initError;
  final StackTrace? initStack;

  const DORApp({
    Key? key,
    required this.firebaseInitialized,
    this.initError,
    this.initStack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'DOR',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Cinzel',
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        routes: {
          '/auth': (context) => const AuthScreen(),
          '/home': (context) => const HomeScreen(),
          '/admin': (context) => const AdminDashboard(),
        },
        home: firebaseInitialized ? const Root() : ErrorScreen(error: initError, stack: initStack),
      ),
    );
  }
}

class Root extends StatelessWidget {
  const Root({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.user == null) {
      return const AuthScreen();
    }

    if (auth.user != null && auth.userData == null) {
      Future.microtask(() => auth.loadUserData());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final role = (auth.userData?['role'] ?? 'staff').toString().toLowerCase();

    if (role == 'manager' || role == 'admin') {
      return const AdminDashboard();
    } else {
      return const HomeScreen();
    }
  }
}

class ErrorScreen extends StatelessWidget {
  final Object? error;
  final StackTrace? stack;

  const ErrorScreen({Key? key, this.error, this.stack}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      debugPrint('Firebase init error (displayed to user): $error');
    }
    if (stack != null) {
      debugPrint('$stack');
    }

    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 72, color: Colors.white70),
                const SizedBox(height: 16),
                const Text(
                  'Initialization error',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The app could not complete startup (Firebase initialization failed). '
                  'Open the browser console for details.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Attempt to move forward; a page refresh may still be required after fixing config
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Root()));
                  },
                  child: const Text('Try to continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
