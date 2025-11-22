// lib/screens/home_screen.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  late final AnimationController _entranceController;
  bool _uploading = false;
  double _uploadProgress = 0.0;

  // branch info loaded from branches/{branchId}
  Map<String, dynamic>? _userBranch; // {id,name,lat,lng}
  String? _branchLoadError;

  // ENFORCED RADIUS: 1000 meters (1 km) — fixed, cannot be changed by user
  static const int _allowedRadiusMeters = 1000;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  String _docIdForToday() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // fetch branch info for signed-in user; call after user signs in or in build via StreamBuilder
  Future<void> _loadUserBranch(String uid, Map<String, dynamic>? userDocData) async {
    setState(() {
      _userBranch = null;
      _branchLoadError = null;
    });

    try {
      final branchId = userDocData?['branchId'] as String?;
      if (branchId == null) {
        setState(() => _branchLoadError = 'No branch assigned to user. Contact admin.');
        return;
      }

      final bSnap = await _db.collection('branches').doc(branchId).get();
      if (!bSnap.exists) {
        setState(() => _branchLoadError = 'Assigned branch not found in database. Contact admin.');
        return;
      }
      final m = bSnap.data()!;
      setState(() {
        _userBranch = {
          'id': bSnap.id,
          'name': m['name'],
          'lat': m['lat'],
          'lng': m['lng'],
        };
      });
    } catch (e) {
      setState(() => _branchLoadError = 'Failed to load branch: $e');
    }
  }

  Future<Position> _determinePositionOrThrow() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Location services are disabled. Please enable location.';
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw 'Location permission denied';
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission permanently denied. Please enable it from system settings.';
    }
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _ensureWithinAssignedBranchOrThrow() async {
    if (_userBranch == null) throw 'Branch not loaded. Contact admin.';
    final pos = await _determinePositionOrThrow();
    final d = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      (_userBranch!['lat'] as num).toDouble(),
      (_userBranch!['lng'] as num).toDouble(),
    );
    if (d > _allowedRadiusMeters) {
      throw 'You are ${d.round()} m away from your assigned branch (${_userBranch!['name']}). You must be within $_allowedRadiusMeters m (1 km) to check in/out.';
    }
    // OK
  }

  /// Upload helpers (same as before)...
  Future<void> _pickAndUploadProfile(String uid) async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;
      await _uploadFileAndSaveUrl(uid, File(picked.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image pick failed: $e')));
    }
  }

  Future<void> _takePhotoAndUpload(String uid) async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;
      await _uploadFileAndSaveUrl(uid, File(picked.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera capture failed: $e')));
    }
  }

  Future<void> _uploadFileAndSaveUrl(String uid, File file) async {
    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = _storage.ref().child('users/$uid/$fileName');

      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.totalBytes > 0 ? snapshot.bytesTransferred / snapshot.totalBytes : 0.0;
        if (mounted) setState(() => _uploadProgress = progress);
      });

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      await _db.collection('users').doc(uid).update({'photoUrl': url});

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() {
        _uploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  // Check-in / check-out functions use assigned branch
  Future<void> _doCheckIn(String uid) async {
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());
    try {
      await _loadUserBranch(uid, (await _db.collection('users').doc(uid).get()).data());
      await _ensureWithinAssignedBranchOrThrow();

      final branch = _userBranch!;
      final branchDistance = await _getDistanceToBranch();

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) {
          final data = snap.data()!;
          if (data['checkIn'] != null) throw ('Already checked in');
          tx.update(docRef, {
            'checkIn': FieldValue.serverTimestamp(),
            'branchId': branch['id'],
            'branchName': branch['name'],
            'branchLat': branch['lat'],
            'branchLng': branch['lng'],
            'branchDistanceMeters': branchDistance,
          });
        } else {
          tx.set(docRef, {
            'date': _docIdForToday(),
            'checkIn': FieldValue.serverTimestamp(),
            'checkOut': null,
            'branchId': branch['id'],
            'branchName': branch['name'],
            'branchLat': branch['lat'],
            'branchLng': branch['lng'],
            'branchDistanceMeters': branchDistance,
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked in — welcome!')));
    } catch (e) {
      if (!mounted) return;
      final msg = (e is String) ? e : 'Check-in failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _doCheckOut(String uid) async {
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());
    try {
      await _loadUserBranch(uid, (await _db.collection('users').doc(uid).get()).data());
      await _ensureWithinAssignedBranchOrThrow();

      final branch = _userBranch!;
      final branchDistance = await _getDistanceToBranch();

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw ('No check-in found for today');
        final data = snap.data()!;
        if (data['checkIn'] == null) throw ('You have not checked in today');
        if (data['checkOut'] != null) throw ('Already checked out');
        tx.update(docRef, {
          'checkOut': FieldValue.serverTimestamp(),
          'checkoutBranchId': branch['id'],
          'checkoutBranchName': branch['name'],
          'checkoutBranchDistanceMeters': branchDistance,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked out — good work!')));
    } catch (e) {
      if (!mounted) return;
      final msg = (e is String) ? e : 'Check-out failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<double> _getDistanceToBranch() async {
    final pos = await _determinePositionOrThrow();
    if (_userBranch == null) return double.infinity;
    final d = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      (_userBranch!['lat'] as num).toDouble(),
      (_userBranch!['lng'] as num).toDouble(),
    );
    return d;
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toLocal();
    return DateFormat.jm().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.user;
    if (user == null) return const Scaffold(body: Center(child: Text('Not signed in')));

    final uid = user.uid;
    final todayDocId = _docIdForToday();
    final dateDisplay = DateFormat.yMMMMEEEEd().format(DateTime.now());

    final userDocStream = _db.collection('users').doc(uid).snapshots();
    final todayDocStream = _db.collection('users').doc(uid).collection('attendance').doc(todayDocId).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DOR — Attendance'),
        actions: [IconButton(onPressed: () => auth.signOut(), icon: const Icon(Icons.logout))],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 22),
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: userDocStream,
              builder: (context, snapshot) {
                String? photoUrl;
                String displayName = user.displayName ?? user.email ?? 'Staff';
                Map<String, dynamic>? userDocData;
                if (snapshot.hasData && snapshot.data!.exists) {
                  userDocData = snapshot.data!.data() as Map<String, dynamic>?;
                  photoUrl = userDocData?['photoUrl'] as String?;
                  displayName = (userDocData?['name'] as String?) ?? displayName;
                  // load branch if not loaded yet
                  if (_userBranch == null) {
                    _loadUserBranch(uid, userDocData);
                  }
                }

                return Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final choice = await showModalBottomSheet<int>(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Wrap(
                                  children: [
                                    ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.of(context).pop(0)),
                                    ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take a photo'), onTap: () => Navigator.of(context).pop(1)),
                                    ListTile(leading: const Icon(Icons.close), title: const Text('Cancel'), onTap: () => Navigator.of(context).pop(-1)),
                                  ],
                                ),
                              ),
                            );

                            if (choice == 0) await _pickAndUploadProfile(uid);
                            if (choice == 1) await _takePhotoAndUpload(uid);
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 34,
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                backgroundImage: (photoUrl != null) ? NetworkImage(photoUrl) as ImageProvider : null,
                                child: (photoUrl == null) ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 20, color: Colors.white)) : null,
                              ),
                              if (_uploading)
                                SizedBox(width: 68, height: 68, child: CircularProgressIndicator(value: _uploadProgress))
                              else
                                Positioned(bottom: -2, right: -2, child: CircleAvatar(radius: 12, backgroundColor: Theme.of(context).colorScheme.secondary, child: const Icon(Icons.edit, size: 14))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hello, $displayName', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(dateDisplay, style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 6),
                              if (_userBranch != null)
                                Text('Assigned branch: ${_userBranch!['name']}', style: Theme.of(context).textTheme.bodySmall)
                              else if (_branchLoadError != null)
                                Text(_branchLoadError!, style: const TextStyle(color: Colors.orangeAccent))
                              else
                                Text('Loading assigned branch...', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        StreamBuilder<DocumentSnapshot>(
                          stream: todayDocStream,
                          builder: (context, snap) {
                            if (!snap.hasData || !snap.data!.exists) return Chip(label: Text('No record'), backgroundColor: Colors.grey.shade800);
                            final m = snap.data!.data() as Map<String, dynamic>;
                            final hasIn = m['checkIn'] != null;
                            final hasOut = m['checkOut'] != null;
                            final label = hasOut ? 'Finished' : (hasIn ? 'Working' : 'Pending');
                            final color = hasOut ? Colors.green : (hasIn ? Colors.orange : Colors.grey);
                            return Chip(label: Text(label), backgroundColor: color.withOpacity(0.15), avatar: CircleAvatar(backgroundColor: color, radius: 8));
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 18),

            // Attendance card (uses today's doc stream)
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(auth.user!.uid).collection('attendance').doc(_docIdForToday()).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  final doc = snapshot.data;
                  Map<String, dynamic>? data = doc?.exists == true ? (doc!.data() as Map<String, dynamic>?) : null;
                  final checkInTs = data?['checkIn'] as Timestamp?;
                  final checkOutTs = data?['checkOut'] as Timestamp?;
                  final hasIn = checkInTs != null;
                  final hasOut = checkOutTs != null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Today', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _TimeTile(label: 'Check In', value: _formatTimestamp(checkInTs), icon: Icons.login, color: Colors.green),
                          const SizedBox(width: 12),
                          _TimeTile(label: 'Check Out', value: _formatTimestamp(checkOutTs), icon: Icons.logout, color: Colors.red),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // show enforced radius and distance info
                      Row(
                        children: [
                          const Text('Required radius: 1 km', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: (_userBranch == null)
                                ? const SizedBox.shrink()
                                : FutureBuilder<double>(
                                    future: _getDistanceToBranch(),
                                    builder: (context, snapDist) {
                                      if (!snapDist.hasData) return const Text('Distance: —');
                                      return Text('Distance to branch: ${snapDist.data!.round()} m');
                                    },
                                  ),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: hasIn ? null : () => _doCheckIn(auth.user!.uid),
                              icon: const Icon(Icons.login),
                              label: Text(hasIn ? 'Checked In' : 'Check In'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasIn && !hasOut ? () => _doCheckOut(auth.user!.uid) : null,
                              icon: const Icon(Icons.logout),
                              label: Text(hasIn ? (hasOut ? 'Checked Out' : 'Check Out') : 'Check Out'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_branchLoadError != null) Text(_branchLoadError!, style: const TextStyle(color: Colors.orangeAccent)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TimeTile({Key? key, required this.label, required this.value, required this.icon, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color, radius: 18, child: Icon(icon, size: 18, color: Colors.white)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
