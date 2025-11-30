import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Updated AuthService that locks a user account to the first device used
/// for sign-up (or first successful sign-in if migrating existing users).
///
/// - Uses flutter_secure_storage to persist a per-device UUID token.
/// - Stores that token in users/{uid}.deviceToken in Firestore.
/// - On sign-in, enforces the device token match (returns an error string if not).
///
/// Note: recovery flows (replace device token) must be protected server-side
/// (OTP/email verification or admin action). The method `replaceDeviceToken`
/// below is a convenience helper that writes a new token to Firestore but
/// includes comments about requiring server-side verification in production.
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// The current Firebase Auth user (nullable)
  User? user;

  /// Cached Firestore user document (users/{uid})
  Map<String, dynamic>? userData;

  /// Loading state for auth-related operations
  bool isLoading = true;

  // Device-locking helpers
  static const String _deviceTokenKey = 'device_token_v1';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

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

  /// Returns the device token stored in secure storage, creating one the
  /// first time this app runs on the device.
  Future<String> _getOrCreateDeviceToken() async {
    String? token = await _secureStorage.read(key: _deviceTokenKey);
    if (token == null) {
      token = _uuid.v4();
      await _secureStorage.write(key: _deviceTokenKey, value: token);
    }
    return token!;
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
      debugPrint('loadUserData error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with email & password. After successful sign-in, load Firestore user doc.
  /// Enforces the per-device lock: if the Firestore user document has a `deviceToken`
  /// and it doesn't match this device's token, sign-in is rejected.
  Future<String?> signIn(String email, String password) async {
    try {
      isLoading = true;
      notifyListeners();

      final deviceToken = await _getOrCreateDeviceToken();

      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final signedInUser = cred.user;
      if (signedInUser == null) return 'Failed to sign in';

      // Fetch Firestore document and check device token
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(signedInUser.uid);
      final snap = await userDocRef.get();

      if (!snap.exists) {
        // No Firestore user document -- create one and set this deviceToken.
        await userDocRef.set({
          'name': signedInUser.displayName ?? '',
          'email': signedInUser.email ?? email,
          'role': 'staff',
          'photoUrl': signedInUser.photoURL,
          'branchId': null,
          'branchName': null,
          'createdAt': FieldValue.serverTimestamp(),
          'deviceToken': deviceToken,
        });
      } else {
        final data = snap.data()!;
        final storedToken = data['deviceToken'] as String?;

        if (storedToken == null) {
          // Migration case: user has no deviceToken stored yet; set it now to lock to this device
          await userDocRef.update({'deviceToken': deviceToken});
        } else if (storedToken != deviceToken) {
          // Device mismatch: immediate sign-out and return a helpful error message
          await _auth.signOut();
          return 'This account is registered on another device. Use account recovery to unlock.';
        }
      }

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
  /// When signing up, the account is immediately locked to this device by saving
  /// this device's token into the Firestore document.
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

      final deviceToken = await _getOrCreateDeviceToken();

      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final newUser = cred.user;
      if (newUser == null) return 'Failed to create user';

      // update display name
      await newUser.updateDisplayName(name);
      await newUser.reload();

      // create Firestore user document with branch info and deviceToken
      final usersRef = FirebaseFirestore.instance.collection('users').doc(newUser.uid);
      await usersRef.set({
        'name': name,
        'email': email,
        'role': 'staff', // default role; promote via admin panel
        'photoUrl': newUser.photoURL,
        'branchId': branchId,
        'branchName': branchName,
        'createdAt': FieldValue.serverTimestamp(),
        'deviceToken': deviceToken,
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

  /// Replace the stored device token for the current user.
  ///
  /// IMPORTANT: In production this should only be callable after a verified
  /// recovery step (OTP/email verification or admin action). Calling this
  /// client-side without server-side checks can allow account takeover.
  Future<String?> replaceDeviceToken({required String verificationProof}) async {
    // `verificationProof` is a placeholder for whatever server-verified proof you use
    // (for example an OTP token you obtained from a backend endpoint).
    if (user == null) return 'Not signed in';

    try {
      isLoading = true;
      notifyListeners();

      // In a safe flow, you'd call your server with the verificationProof and
      // the server would validate and then update Firestore (or return permission)
      // Here we show a local helper that updates Firestore directly. Use with care.

      // Generate a new device token for this device and write it to Firestore
      final newToken = await _getOrCreateDeviceToken();

      // NOTE: This write should be guarded by server-side verification in production.
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      await userDocRef.update({'deviceToken': newToken});

      // refresh local cache
      await loadUserData();

      return null;
    } catch (e) {
      return e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
