// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // <-- Added for platform detection

import 'admin_dashboard.dart';
import 'home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorText;
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Updated function: works on Android, iOS, Windows, macOS, Linux, Web
  Future<String> getCustomDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId = '';

    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      rawId =
          '${webInfo.userAgent ?? ''}-${webInfo.hardwareConcurrency ?? ''}-${webInfo.platform ?? ''}';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final androidInfo = await deviceInfo.androidInfo;
          rawId =
              '${androidInfo.id}-${androidInfo.board}-${androidInfo.brand}-${androidInfo.device}-${androidInfo.hardware}-${androidInfo.manufacturer}-${androidInfo.model}';
          break;
        case TargetPlatform.iOS:
          final iosInfo = await deviceInfo.iosInfo;
          rawId = '${iosInfo.identifierForVendor}-${iosInfo.name}';
          break;
        case TargetPlatform.windows:
          final windowsInfo = await deviceInfo.windowsInfo;
          rawId = '${windowsInfo.deviceId}-${windowsInfo.computerName}';
          break;
        case TargetPlatform.macOS:
          final macOsInfo = await deviceInfo.macOsInfo;
          rawId = '${macOsInfo.systemGUID}-${macOsInfo.computerName}';
          break;
        case TargetPlatform.linux:
          final linuxInfo = await deviceInfo.linuxInfo;
          rawId = '${linuxInfo.machineId}-${linuxInfo.name}';
          break;
        default:
          rawId = 'unsupported-platform';
      }
    }

    final bytes = utf8.encode(rawId);
    final hashedId = sha256.convert(bytes).toString();
    return hashedId;
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Please enter both email and password');
      return;
    }

    setState(() {
      _errorText = null;
      _isLoading = true;
    });

    try {
      final deviceId = await getCustomDeviceId();

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user!.uid;
      final docRef = FirebaseFirestore.instance.collection('Users').doc(uid);
      final doc = await docRef.get();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!doc.exists) {
        setState(() => _errorText = 'No user profile found for this account.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final data = doc.data()!;
      final storedDeviceId = data['deviceId'] as String?;
      final bool isAdmin = data['isAdmin'] == true;

      if (!isAdmin) {
        if (storedDeviceId == null || storedDeviceId.isEmpty) {
          await docRef.update({'deviceId': deviceId});
        } else if (storedDeviceId != deviceId) {
          setState(() => _errorText = 'Login allowed only from your registered device.');
          await FirebaseAuth.instance.signOut();
          return;
        }
      }

      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => isAdmin ? const AdminDashboard() : const HomePage()));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = e.code == 'user-not-found'
            ? 'No user found for that email.'
            : e.code == 'wrong-password'
                ? 'Wrong password provided.'
                : e.code == 'invalid-email'
                    ? 'Invalid email address.'
                    : 'Login failed: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Container(
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/images/logo.jpeg',
                      height: 150,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Login to Proceed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      color: const Color.fromARGB(255, 43, 5, 94),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color.fromARGB(255, 43, 5, 94), width: 2.0),
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color.fromARGB(255, 43, 5, 94), width: 2.0),
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: const Color.fromARGB(255, 43, 5, 94),
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 24),
                  if (_errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        _errorText!,
                        style: const TextStyle(
                          color: Color.fromARGB(255, 165, 17, 7),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Color.fromARGB(255, 43, 5, 94)),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: const Color.fromARGB(255, 43, 5, 94),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: const Text(
                            'Login',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
