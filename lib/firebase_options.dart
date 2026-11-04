// File generated from your existing web Firebase config (project: khurram-world).
//
// IMPORTANT (Android):
//   The `android` values below are placeholders. The correct way to wire Android
//   is to run `flutterfire configure` OR register an Android app in the Firebase
//   console and place the downloaded `google-services.json` in android/app/.
//   When google-services.json is present, Android uses it automatically and these
//   android values are not strictly required. See README section 3.
//
// The web values are your real ones and are safe to keep.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  // Real values from your deployed web app.

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCf_RlgHv5X7ie7xa9rQJE6NNkiCqJmtI0',
    appId: '1:217678871138:web:f4787814bfe80059d4af3b',
    messagingSenderId: '217678871138',
    projectId: 'khurram-world',
    authDomain: 'khurram-world.firebaseapp.com',
    databaseURL: 'https://khurram-world-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'khurram-world.firebasestorage.app',
    measurementId: 'G-RPDMNN90K8',
  );
  // Android: prefer google-services.json. If you run `flutterfire configure`,
  // it will overwrite this file with the correct android appId.

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA2g_5EUkrqHOIEPnBppN9ChLDJXQo7rbc',
    appId: '1:217678871138:android:2c76e51cbafa0943d4af3b',
    messagingSenderId: '217678871138',
    projectId: 'khurram-world',
    databaseURL: 'https://khurram-world-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'khurram-world.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAgczxQmvasR2YQc_zzInaPShGBWEbGC68',
    appId: '1:217678871138:ios:e7602f6ef182481fd4af3b',
    messagingSenderId: '217678871138',
    projectId: 'khurram-world',
    databaseURL: 'https://khurram-world-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'khurram-world.firebasestorage.app',
    iosClientId: '217678871138-5cnaedf6dqlmsrm5cqtnrguerf93etsv.apps.googleusercontent.com',
    iosBundleId: 'com.khurram.dailyhub',
  );
}
