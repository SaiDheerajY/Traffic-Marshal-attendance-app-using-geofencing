// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'login.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- State Variables ---
  bool _isWithinGeofence = false;
  bool _wasWithinGeofence = false; // <-- Added for auto-checkout
  bool _isCheckingLocation = true;
  bool _isCheckedIn = false; // Tracks local UI state for check-in
  String _statusMessage = 'Checking location...';

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription; // <-- NEW
  Timer? _hourlyCheckTimer;
  Timer? _checkInDurationTimer;

  // Default Geofence coordinates and radius (Hyderabad location)
  // These will be overridden by user-specific work location if available.
  double _geofenceLatitude = 17.431634;
  double _geofenceLongitude = 78.369531;
  final double geofenceRadius = 250; // meters

  DateTime? _checkInTime; // Stores the local check-in time for duration calculation
  Duration _elapsed = Duration.zero;
  Position? _currentPosition;
  double? _currentDistance;

  String _userWorkLocationDisplay = 'Default (Hyderabad)'; // To display on UI

  bool _isDarkMode = true; // Controls the current theme mode

  @override
  void initState() {
    super.initState();
    _checkInitialCheckInStatus(); // Check if user was checked in from previous session
    _fetchUserWorkLocationAndCheck(); // Fetch user's work location and then check current location
    _listenToLocationServiceStatus(); // <-- NEW
  }

  @override
  void dispose() {
    _stopLocationMonitoring(); // Cancel location stream
    _checkInDurationTimer?.cancel(); // Cancel check-in timer
    _hourlyCheckTimer?.cancel(); // Cancel hourly location check timer
    _serviceStatusSubscription?.cancel(); // <-- NEW
    super.dispose();
  }

  // --- Listen for Location Service Status Changes ---
  void _listenToLocationServiceStatus() {
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.disabled) {
        // Auto-checkout if checked in and location is turned off
        if (_isCheckedIn) {
          _checkOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location turned off. You have been automatically checked out.'),
            ),
          );
        }
        setState(() {
          _isWithinGeofence = false; // Prevent check-in
          _statusMessage = 'Location service is OFF. Please enable location to check in.';
        });
      } else if (status == ServiceStatus.enabled) {
        // Optionally re-check geofence
        _checkLocation();
      }
    });
  }

  // --- Utility Methods ---
  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes % 60)}:${twoDigits(duration.inSeconds % 60)}';
  }

  String _formatLocation(Position? position) {
    if (position == null) return 'Unknown Location';
    return '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
  }

  // --- Location and Geofencing Logic ---

  Future<void> _fetchUserWorkLocationAndCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (kDebugMode) {
        print("User not logged in, cannot fetch work location.");
      }
      setState(() {
        _statusMessage = 'User not logged in. Please log in.';
        _isCheckingLocation = false;
      });
      return;
    }

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final double? workLat = userData['workLatitude'] as double?;
        final double? workLon = userData['workLongitude'] as double?;

        if (workLat != null && workLon != null) {
          setState(() {
            _geofenceLatitude = workLat;
            _geofenceLongitude = workLon;
            _userWorkLocationDisplay =
                'Assigned: ${workLat.toStringAsFixed(4)}, ${workLon.toStringAsFixed(4)}';
          });
          if (kDebugMode) {
            print("Using assigned work location: $_geofenceLatitude, $_geofenceLongitude");
          }
        } else {
          if (kDebugMode) {
            print("No specific work location found for user. Using default.");
          }
          setState(() {
            _geofenceLatitude = 17.431; // Default Hyderabad
            _geofenceLongitude = 78.369; // Default Hyderabad
            _userWorkLocationDisplay = 'Default (Hyderabad)';
          });
        }
      } else {
        if (kDebugMode) {
          print("User document not found. Using default work location.");
        }
        setState(() {
          _geofenceLatitude = 17.431634; // Default Hyderabad
          _geofenceLongitude = 78.369531; // Default Hyderabad
          _userWorkLocationDisplay = 'Default';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching user work location: $e");
      }
      setState(() {
        _statusMessage = 'Error fetching work location: $e';
        _isCheckingLocation = false;
      });
      // Fallback to default if there's an error fetching
      _geofenceLatitude = 17.431634;
      _geofenceLongitude = 78.369531;
      _userWorkLocationDisplay = 'Default (Hyderabad) - Error fetching assigned';
    } finally {
      _checkLocation();
    }
  }

  Future<void> _checkLocation() async {
    setState(() {
      _isCheckingLocation = true;
      _statusMessage = 'Checking location...';
    });

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = 'Location permissions are denied';
          _isCheckingLocation = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage =
            'Location permissions are permanently denied. Please enable from settings.';
        _isCheckingLocation = false;
      });
      return;
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _currentDistance = Geolocator.distanceBetween(
          _geofenceLatitude,
          _geofenceLongitude,
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );

        setState(() {
          _isWithinGeofence = _currentDistance! <= geofenceRadius;
          _wasWithinGeofence = _isWithinGeofence; // <-- Initialize for auto-checkout
          _statusMessage = _isWithinGeofence
              ? 'Within geofence (Distance: ${_currentDistance!.toStringAsFixed(2)} m)'
              : 'Outside geofence (Distance: ${_currentDistance!.toStringAsFixed(2)} m)';
          _isCheckingLocation = false;
        });

        if (_isWithinGeofence && _positionStreamSubscription == null) {
          _startLocationMonitoring();
        } else if (!_isWithinGeofence && _positionStreamSubscription != null) {
          _stopLocationMonitoring();
        }
      } catch (e) {
        setState(() {
          _statusMessage = 'Error getting location: $e';
          _isCheckingLocation = false;
        });
        if (kDebugMode) {
          print("Error getting location: $e");
        }
      }
    }
  }

  void _startLocationMonitoring() {
    if (_positionStreamSubscription != null) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        setState(() {
          _currentPosition = position;
          _currentDistance = Geolocator.distanceBetween(
            _geofenceLatitude,
            _geofenceLongitude,
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
          _isWithinGeofence = _currentDistance! <= geofenceRadius;
          _statusMessage = _isWithinGeofence
              ? 'Within geofence (Distance: ${_currentDistance!.toStringAsFixed(2)} m)'
              : 'Outside geofence (Distance: ${_currentDistance!.toStringAsFixed(2)} m)';
        });

        // --- AUTO-CHECKOUT LOGIC ---
        if (_wasWithinGeofence && !_isWithinGeofence && _isCheckedIn) {
          _checkOut();
        }
        _wasWithinGeofence = _isWithinGeofence;
      },
      onError: (error) {
        if (kDebugMode) {
          print("Error in location stream: $error");
        }
        setState(() {
          _statusMessage = 'Location stream error: $error';
        });
      },
      onDone: () {
        if (kDebugMode) {
          print("Location stream done.");
        }
      },
    );
  }

  void _stopLocationMonitoring() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  // --- Persistence Logic: Check Initial Check-in Status from Firestore ---
  Future<void> _checkInitialCheckInStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isCheckedIn = false;
      });
      return;
    }

    try {
      final QuerySnapshot result = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .collection('attendance')
          .where('checkOutTime', isNull: true)
          .orderBy('checkInTime', descending: true)
          .limit(1)
          .get();

      if (result.docs.isNotEmpty) {
        final Map<String, dynamic> data = result.docs.first.data() as Map<String, dynamic>;
        setState(() {
          _isCheckedIn = true;
          _checkInTime = (data['checkInTime'] as Timestamp).toDate();
          _elapsed = DateTime.now().difference(_checkInTime!);
        });

        _checkInDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_checkInTime != null) {
            setState(() {
              _elapsed = DateTime.now().difference(_checkInTime!);
            });
          }
        });

        _hourlyCheckTimer ??= Timer.periodic(const Duration(hours: 1), (timer) {
          _checkLocation();
        });

        if (kDebugMode) {
          print('User was already checked in since: $_checkInTime');
        }
      } else {
        setState(() {
          _isCheckedIn = false;
        });
        if (kDebugMode) {
          print('User is not currently checked in.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking initial check-in status: $e');
      }
      setState(() {
        _isCheckedIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading check-in status: $e')),
      );
    }
  }

  // --- Check-in/Check-out Logic with Firestore Integration ---

  void _checkIn() async {
    if (!_isWithinGeofence || _isCheckingLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot check in: Not within geofence or location still checking.')),
      );
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot check in: Current location not available.')),
      );
      return;
    }

    setState(() {
      _statusMessage = 'Attempting check-in...';
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not logged in.')),
      );
      return;
    }

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
      String userName =
          (userDoc.data() as Map<String, dynamic>?)?['Name'] as String? ?? 'Unknown User';

      String checkInLocationString = _formatLocation(_currentPosition);

      await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .collection('attendance')
          .add({
        'Name': userName,
        'checkInTime': Timestamp.now(),
        'checkOutTime': null,
        'checkInLocation': checkInLocationString,
        'checkOutLocation': null,
      });

      setState(() {
        _isCheckedIn = true;
        _checkInTime = DateTime.now();
        _elapsed = Duration.zero;
        _statusMessage = 'Checked in successfully!';
      });

      _checkInDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_checkInTime != null) {
          setState(() {
            _elapsed = DateTime.now().difference(_checkInTime!);
          });
        }
      });

      _hourlyCheckTimer ??= Timer.periodic(const Duration(hours: 1), (timer) {
        _checkLocation();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checked in as $userName from $checkInLocationString')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error during check-in: $e');
      }
      setState(() {
        _statusMessage = 'Check-in failed: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-in failed: ${e.toString()}')),
      );
    }
  }

  void _checkOut() async {
    if (!_isCheckedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot check out: Not currently checked in.')),
      );
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot check out: Current location not available.')),
      );
      return;
    }

    setState(() {
      _statusMessage = 'Attempting check-out...';
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not logged in.')),
      );
      return;
    }

    try {
      String checkOutLocationString = _formatLocation(_currentPosition);

      final QuerySnapshot result = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .collection('attendance')
          .where('checkOutTime', isNull: true)
          .orderBy('checkInTime', descending: true)
          .limit(1)
          .get();

      if (result.docs.isNotEmpty) {
        final DocumentSnapshot attendanceDocToUpdate = result.docs.first;
        await attendanceDocToUpdate.reference.update({
          'checkOutTime': Timestamp.now(),
          'checkOutLocation': checkOutLocationString,
        });

        setState(() {
          _isCheckedIn = false;
          _checkInTime = null;
          _elapsed = Duration.zero;
          _statusMessage = 'Checked out successfully!';
        });

        _checkInDurationTimer?.cancel();
        _hourlyCheckTimer?.cancel();
        _hourlyCheckTimer = null;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checked out from $checkOutLocationString')),
        );
      } else {
        setState(() {
          _statusMessage = 'No active check-in found to check out from.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active check-in found to check out from.')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during check-out: $e');
      }
      setState(() {
        _statusMessage = 'Check-out failed: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-out failed: ${e.toString()}')),
      );
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.blue,
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        accentColor: Colors.teal,
        brightness: Brightness.light,
      ).copyWith(
        background: Colors.white,
        surface: Colors.white,
        onBackground: Colors.black87,
        onSurface: Colors.black87,
        error: Colors.red[700]!,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.blue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 5,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        labelStyle: TextStyle(color: Colors.grey[600]),
        hintStyle: TextStyle(color: Colors.grey[400]),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black87),
        titleMedium: TextStyle(color: Colors.black87),
        displayLarge: TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
    );
  }

  ThemeData _darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.blueGrey,
      scaffoldBackgroundColor: Colors.blueGrey[900],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.amber,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 5,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.tealAccent[100]),
        bodyMedium: TextStyle(color: Colors.tealAccent[100]),
        titleMedium: TextStyle(color: Colors.tealAccent[100]),
        displayLarge: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.blueGrey[700],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blueGrey[600]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.tealAccent[400]!, width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white38),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.blueGrey[800],
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
    );
  }

  ButtonStyle primaryActionButtonStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 5,
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDarkMode ? _darkTheme() : _lightTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Traffic Marshal Home'),
          leading: IconButton(
            icon: Icon(
              _isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              setState(() {
                _isDarkMode = !_isDarkMode;
              });
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              color: Colors.red,
              onPressed: _logout,
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/logo.jpeg',
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.traffic,
                        size: 100,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Display assigned work location
                Text(
                  'Work Location: $_userWorkLocationDisplay',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                ),
                const SizedBox(height: 16),

                // Status Message (Within/Outside Geofence)
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _isWithinGeofence ? Colors.green[600] : Colors.red[600],
                  ),
                ),
                const SizedBox(height: 24),

                // Loading Indicator or Geofence Status Message
                if (_isCheckingLocation)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  )
                else if (!_isWithinGeofence)
                  Text(
                    'You are outside the designated geofence. Cannot check in.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                const SizedBox(height: 32),

                // Action Buttons
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Check In'),
                      style: primaryActionButtonStyle(),
                      onPressed: (!_isCheckedIn && _isWithinGeofence && !_isCheckingLocation)
                          ? _checkIn
                          : null,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Check Out'),
                      style: primaryActionButtonStyle(),
                      onPressed: _isCheckedIn ? _checkOut : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Location'),
                      style: primaryActionButtonStyle(),
                      onPressed: _isCheckingLocation ? null : _fetchUserWorkLocationAndCheck,
                    ),
                    const SizedBox(height: 20),

                    // Timer Text (Checked in for:)
                    if (_isCheckedIn && _checkInTime != null)
                      Text(
                        'Checked in for: ${formatDuration(_elapsed)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color:
                              _isDarkMode ? const Color.fromARGB(255, 255, 255, 255) : Colors.black,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
