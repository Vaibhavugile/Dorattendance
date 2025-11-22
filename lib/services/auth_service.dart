// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? user;
  bool isLoading = true;

  AuthService() {
    _auth.authStateChanges().listen((u) {
      user = u;
      isLoading = false;
      notifyListeners();
    });
  }

  Future<String?> signIn(String email, String password) async {
    try {
      isLoading = true;
      notifyListeners();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Updated signUp: accepts branchId and branchName and stores them in Firestore users/{uid}
  Future<String?> signUp(String name, String email, String password, {required String branchId, required String branchName}) async {
    try {
      isLoading = true;
      notifyListeners();

      // Create user in Firebase Auth
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUser = cred.user;
      if (newUser == null) return 'Failed to create user';

      // Update display name in Auth
      await newUser.updateDisplayName(name);
      await newUser.reload();

      // Create Firestore user document with branch info
      final usersRef = FirebaseFirestore.instance.collection('users').doc(newUser.uid);
      await usersRef.set({
        'name': name,
        'email': email,
        'role': 'staff', // default
        'photoUrl': null,
        'branchId': branchId,
        'branchName': branchName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
