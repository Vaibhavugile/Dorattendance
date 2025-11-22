import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

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
          // create a ColorScheme with explicit dark brightness so there is no mismatch
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          // You can also customize textTheme here if you like:
          // textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
        ),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: auth.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (auth.user == null ? const AuthScreen() : const HomeScreen()),
    );
  }
}
