# Traffic Marshal Attendance App

A Flutter + Firebase attendance application for traffic marshals that uses geofencing to make check-in/check-out location-aware.

## Features

- Firebase Authentication and Firestore-backed attendance records
- User-specific assigned work locations with a default Hyderabad location
- 250 m geofence validation before check-in
- Continuous location monitoring while checked in
- Automatic check-out when the user leaves the geofence or disables location services
- Check-in duration tracking and persistence across app sessions
- Admin attendance management and Excel export
- Light/dark UI support

## Tech Stack

- Flutter / Dart
- Firebase Core, Authentication, and Cloud Firestore
- Geolocator + permission_handler
- Google Sign-In
- Excel / Syncfusion XLSX utilities
- fl_chart

## Getting Started

### Prerequisites

- Flutter SDK compatible with Dart 3.5+
- A Firebase project
- Android Studio or another Flutter-compatible IDE

### Setup

```bash
git clone https://github.com/SaiDheerajY/Traffic-Marshal-attendance-app-using-geofencing.git
cd Traffic-Marshal-attendance-app-using-geofencing
flutter pub get
```

Configure Firebase for the project:

```bash
flutterfire configure
```

This generates the `lib/firebase_options.dart` file used during Firebase initialization.

Run the application:

```bash
flutter run
```

## How It Works

1. The user signs in and the app loads the work-location coordinates stored for that user.
2. The current device location is compared with the assigned location.
3. Check-in is allowed only when the device is inside the configured geofence.
4. Attendance timestamps and coordinates are stored in Firestore.
5. While checked in, the app monitors location changes and automatically checks the user out if the geofence is exited.

## Notes

Location permissions and location services must be enabled for geofence-based attendance to work correctly. Firebase credentials/configuration are intentionally environment-specific and should not be committed as secrets.
