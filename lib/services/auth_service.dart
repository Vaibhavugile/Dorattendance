import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// The current Firebase Auth user (nullable)
  User? user;

  /// Cached Firestore user document (users/{uid})
  Map<String, dynamic>? userData;

  /// Loading state for auth-related operations
  bool isLoading = true;

  AuthService() {
    // Listen to auth state changes and keep user / userData in sync
    _auth.authStateChanges().listen((u) {
      user = u;
      if (user != null) {
        // load Firestore user document when signed in
        loadUserData();
      } else {
        // clear cached userData when signed out
        userData = null;
        isLoading = false;
        notifyListeners();
      }
    });
  }

  /// Loads the Firestore users/{uid} document for the current user
  Future<void> loadUserData() async {
    if (user == null) return;
    try {
      isLoading = true;
      notifyListeners();

      final snap = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (snap.exists) {
        userData = snap.data();
      } else {
        userData = null;
      }
    } catch (e) {
      // keep userData null on error, but surface if needed
      userData = null;
      // optionally log error to console:
      // debugPrint('loadUserData error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with email & password. After successful sign-in, load Firestore user doc.
  Future<String?> signIn(String email, String password) async {
    try {
      isLoading = true;
      notifyListeners();

      await _auth.signInWithEmailAndPassword(email: email, password: password);

      // load Firestore user document (role, branch, etc.)
      await loadUserData();

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    } finally {
      // loadUserData sets isLoading=false at the end, but ensure we're consistent
      isLoading = false;
      notifyListeners();
    }
  }

  /// Sign up and save branch selection into users/{uid}. After creation, load Firestore user doc.
  Future<String?> signUp(
    String name,
    String email,
    String password, {
    required String branchId,
    required String branchName,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final newUser = cred.user;
      if (newUser == null) return 'Failed to create user';

      // update display name
      await newUser.updateDisplayName(name);
      await newUser.reload();

      // create Firestore user document with branch info
      final usersRef = FirebaseFirestore.instance.collection('users').doc(newUser.uid);
      await usersRef.set({
        'name': name,
        'email': email,
        'role': 'staff', // default role; promote via admin panel
        'photoUrl': null,
        'branchId': branchId,
        'branchName': branchName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // load freshly created user document into cache
      await loadUserData();

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

  /// Sign out and clear cached userData
  Future<void> signOut() async {
    await _auth.signOut();
    userData = null;
    user = null;
    notifyListeners();
  }
}
