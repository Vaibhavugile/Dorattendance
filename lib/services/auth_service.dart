import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? user;
  Map<String, dynamic>? userData;
  bool isLoading = true;

  AuthService() {
    _auth.authStateChanges().listen((u) {
      user = u;
      if (user != null) {
        loadUserData();
      } else {
        userData = null;
        isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<String> _getLocalDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('deviceId');
    if (id != null) return id;
    id = Random().nextInt(999999999).toString();
    await prefs.setString('deviceId', id);
    return id;
  }

  Future<void> loadUserData() async {
    if (user == null) return;
    try {
      isLoading = true;
      notifyListeners();

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (snap.exists) {
        userData = snap.data();
      } else {
        userData = null;
      }
    } catch (e) {
      userData = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      isLoading = true;
      notifyListeners();

      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);

      user = cred.user;
      if (user == null) return "User not found";

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (!snap.exists) return "User data not found";

      String serverId = snap['deviceId'];
      String localId = await _getLocalDeviceId();

      if (serverId != localId) {
        await _auth.signOut();
        user = null;
        return "This account can only be used on the original device.";
      }

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

      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);

      final newUser = cred.user;
      if (newUser == null) return 'Failed to create user';

      await newUser.updateDisplayName(name);
      await newUser.reload();

      String deviceId = await _getLocalDeviceId();

      final usersRef =
          FirebaseFirestore.instance.collection('users').doc(newUser.uid);

      await usersRef.set({
        'name': name,
        'email': email,
        'role': 'staff',
        'photoUrl': null,
        'branchId': branchId,
        'branchName': branchName,
        'createdAt': FieldValue.serverTimestamp(),
        'deviceId': deviceId,
      });

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

  Future<void> signOut() async {
    await _auth.signOut();
    userData = null;
    user = null;
    notifyListeners();
  }
}