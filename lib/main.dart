import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'admin/admin_dashboard.dart';

// import 'firebase_options.dart'; // uncomment if you generated this via flutterfire

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    // options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const DORApp());
}

class DORApp extends StatelessWidget {
  const DORApp({Key? key}) : super(key: key);

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
          // create a ColorScheme with explicit dark brightness so there is no mismatch
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        // central route names so other parts of app can use Navigator.pushNamed(...)
        routes: {
          '/auth': (context) => const AuthScreen(),
          '/home': (context) => const HomeScreen(),
          '/admin': (context) => const AdminDashboard(),
        },
        home: const Root(),
      ),
    );
  }
}

class Root extends StatelessWidget {
  const Root({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    // still initializing FirebaseAuth state / listener
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // not signed in -> show auth screen
    if (auth.user == null) {
      return const AuthScreen();
    }

    // user is signed in but we haven't loaded the Firestore user doc (role, branch, etc.)
    // trigger loadUserData() once and show a loader while it finishes
    if (auth.user != null && auth.userData == null) {
      // schedule a load without blocking build
      Future.microtask(() => auth.loadUserData());
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // At this point auth.user != null and auth.userData is available (or empty)
    final role = (auth.userData?['role'] ?? 'staff').toString().toLowerCase();

    if (role == 'manager' || role == 'admin') {
      return const AdminDashboard();
    } else {
      return const HomeScreen();
    }
  }
}
