import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/config.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.firebaseMode) {
    try {
      // Requires the Android Firebase app (app.fmate) to be registered and
      // google-services.json plus the Google Services Gradle plugin configured.
      await Firebase.initializeApp();
      // Do not persist chat/post caches on shared exhibition devices.
      FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
      if (AppConfig.exhibitionKiosk) await FirebaseAuth.instance.signOut();
    } catch (error) {
      runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Firebase 초기화에 실패했어요. Android 앱 등록 및 google-services.json을 확인하세요.\n$error',
            textAlign: TextAlign.center),
      )))));
      return;
    }
  }
  runApp(const FMateApp());
}
