import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

// IMPORTANT: You MUST generate this file by running 'flutterfire configure' in your project root.
// This command requires Firebase CLI to be installed and logged in.
import 'firebase_options.dart';
import 'login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp()); // Added const here
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Traffic Marshal App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginPage(), // Added const here
    );
  }
}
