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

  // Branch info loaded once
  Map<String, dynamic>? _userBranch; // {id,name,lat,lng}
  String? _branchLoadError;
  String? _lastLoadedBranchId; // <=== FIX prevents reloading every rebuild

  // Fixed radius 1 km
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

  // *** FIX: Safe load called only once per branchId ***
  void _tryLoadBranchOnce(String uid, Map<String, dynamic>? userDoc) {
    final branchId = userDoc?['branchId'];
    if (branchId == null) return;

    if (_lastLoadedBranchId == branchId) {
      return; // Already loaded
    }

    _lastLoadedBranchId = branchId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserBranch(uid, userDoc);
    });
  }

  Future<void> _loadUserBranch(String uid, Map<String, dynamic>? userDocData) async {
    try {
      final branchId = userDocData?['branchId'] as String?;
      if (branchId == null) {
        setState(() => _branchLoadError = 'No branch assigned. Contact admin.');
        return;
      }

      final bSnap = await _db.collection('branches').doc(branchId).get();
      if (!bSnap.exists) {
        setState(() => _branchLoadError = 'Branch not found. Contact admin.');
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
        _branchLoadError = null;
      });
    } catch (e) {
      setState(() => _branchLoadError = 'Failed to load branch: $e');
    }
  }

  Future<Position> _determinePositionOrThrow() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled.';
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw 'Location permission denied.';
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Permission permanently denied. Enable manually.';
    }

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _ensureWithinAssignedBranchOrThrow() async {
    if (_userBranch == null) throw 'Branch not loaded yet.';

    final pos = await _determinePositionOrThrow();
    final d = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      (_userBranch!['lat'] as num).toDouble(),
      (_userBranch!['lng'] as num).toDouble(),
    );

    if (d > _allowedRadiusMeters) {
      throw 'You are ${d.round()} m away. Must be inside 1 km to check-in/out.';
    }
  }

  // ============================
  // Profile upload helpers
  // ============================
  Future<void> _pickAndUploadProfile(String uid) async {
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;
      await _uploadFileAndSaveUrl(uid, File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image pick failed: $e')));
      }
    }
  }

  Future<void> _takePhotoAndUpload(String uid) async {
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;
      await _uploadFileAndSaveUrl(uid, File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera failed: $e')));
      }
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
        final progress = (snapshot.totalBytes > 0)
            ? snapshot.bytesTransferred / snapshot.totalBytes
            : 0.0;
        if (mounted) setState(() => _uploadProgress = progress);
      });

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      await _db.collection('users').doc(uid).update({'photoUrl': url});

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  // ============================
  // Attendance
  // ============================
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

  Future<void> _doCheckIn(String uid) async {
    debugPrint("[_doCheckIn] called uid=$uid");
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());

    try {
      // Reload branch safely before checking in
      final ud = (await _db.collection('users').doc(uid).get()).data();
      _tryLoadBranchOnce(uid, ud);

      await _ensureWithinAssignedBranchOrThrow();

      final branch = _userBranch!;
      final branchDistance = await _getDistanceToBranch();

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        if (snap.exists && snap.data()!['checkIn'] != null) {
          throw 'You already checked in.';
        }

        tx.set(
          docRef,
          {
            'date': _docIdForToday(),
            'checkIn': FieldValue.serverTimestamp(),
            'checkOut': null,
            'branchId': branch['id'],
            'branchName': branch['name'],
            'branchLat': branch['lat'],
            'branchLng': branch['lng'],
            'branchDistanceMeters': branchDistance,
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Checked in successfully!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _doCheckOut(String uid) async {
    debugPrint("[_doCheckOut] called uid=$uid");
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());

    try {
      // Reload branch safely before checking out
      final ud = (await _db.collection('users').doc(uid).get()).data();
      _tryLoadBranchOnce(uid, ud);

      await _ensureWithinAssignedBranchOrThrow();

      final branch = _userBranch!;
      final branchDistance = await _getDistanceToBranch();

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        if (!snap.exists || snap.data()!['checkIn'] == null) {
          throw 'You have not checked in today.';
        }
        if (snap.data()!['checkOut'] != null) throw 'Already checked out.';

        tx.update(docRef, {
          'checkOut': FieldValue.serverTimestamp(),
          'checkoutBranchId': branch['id'],
          'checkoutBranchName': branch['name'],
          'checkoutBranchDistanceMeters': branchDistance,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Checked out successfully!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toLocal();
    return DateFormat.jm().format(dt);
  }

  // ============================
  // UI
  // ============================
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.user;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    final uid = user.uid;
    final userDocStream = _db.collection('users').doc(uid).snapshots();
    final todayDocStream =
        _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday()).snapshots();
    final dateDisplay = DateFormat.yMMMMEEEEd().format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text("DOR — Attendance"),
        actions: [
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(
          children: [
            // ============= PROFILE CARD ==============
            StreamBuilder<DocumentSnapshot>(
              stream: userDocStream,
              builder: (context, snapshot) {
                String? photoUrl;
                String displayName = user.displayName ?? "Staff";
                Map<String, dynamic>? userDoc;

                if (snapshot.hasData && snapshot.data!.exists) {
                  userDoc = snapshot.data!.data() as Map<String, dynamic>;
                  photoUrl = userDoc['photoUrl'];
                  displayName = userDoc['name'] ?? displayName;

                  // FIX: Only load branch after build frame
                  _tryLoadBranchOnce(uid, userDoc);
                }

                return _buildProfileCard(photoUrl, displayName, dateDisplay, uid);
              },
            ),

            const SizedBox(height: 18),

            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: todayDocStream,
                builder: (context, snapshot) {
                  final doc = snapshot.data;
                  final data =
                      (doc != null && doc.exists) ? doc.data() as Map<String, dynamic> : null;

                  final checkInTs = data?['checkIn'];
                  final checkOutTs = data?['checkOut'];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("Today", style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          _TimeTile(
                            label: "Check In",
                            value: _formatTimestamp(checkInTs),
                            color: Colors.green,
                            icon: Icons.login,
                          ),
                          const SizedBox(width: 10),
                          _TimeTile(
                            label: "Check Out",
                            value: _formatTimestamp(checkOutTs),
                            color: Colors.red,
                            icon: Icons.logout,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          const Text("Required radius: 1 km",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _userBranch == null
                                ? const Text("Distance: —")
                                : FutureBuilder<double>(
                                    future: _getDistanceToBranch(),
                                    builder: (context, s) {
                                      if (!s.hasData) return const Text("Distance: —");
                                      return Text(
                                        "Distance: ${s.data!.round()} m",
                                        style:
                                            const TextStyle(fontWeight: FontWeight.w600),
                                      );
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
                              onPressed: (checkInTs != null)
                                  ? null
                                  : () => _doCheckIn(uid),
                              icon: const Icon(Icons.login),
                              label:
                                  Text(checkInTs != null ? "Checked In" : "Check In"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (checkInTs != null && checkOutTs == null)
                                  ? () => _doCheckOut(uid)
                                  : null,
                              icon: const Icon(Icons.logout),
                              label: Text(checkOutTs != null
                                  ? "Checked Out"
                                  : "Check Out"),
                            ),
                          )
                        ],
                      ),

                      if (_branchLoadError != null) ...[
                        const SizedBox(height: 12),
                        Text(_branchLoadError!,
                            style: const TextStyle(color: Colors.orangeAccent)),
                      ]
                    ],
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Profile card widget
  // =====================================================
  Widget _buildProfileCard(String? photoUrl, String name, String dateDisplay, String uid) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface,
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
                        ListTile(
                          leading: const Icon(Icons.photo_library),
                          title: const Text("Choose from gallery"),
                          onTap: () => Navigator.pop(context, 0),
                        ),
                        ListTile(
                          leading: const Icon(Icons.camera_alt),
                          title: const Text("Take photo"),
                          onTap: () => Navigator.pop(context, 1),
                        ),
                        ListTile(
                          leading: const Icon(Icons.close),
                          title: const Text("Cancel"),
                          onTap: () => Navigator.pop(context, -1),
                        ),
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
                    backgroundColor: Colors.blue,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: (photoUrl == null)
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 22),
                          )
                        : null,
                  ),
                  if (_uploading)
                    SizedBox(
                        width: 68,
                        height: 68,
                        child: CircularProgressIndicator(value: _uploadProgress))
                ],
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Hello, $name",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(dateDisplay),
                  const SizedBox(height: 6),
                  if (_userBranch != null)
                    Text("Branch: ${_userBranch!['name']}")
                  else if (_branchLoadError != null)
                    Text(_branchLoadError!,
                        style: const TextStyle(color: Colors.orangeAccent))
                  else
                    const Text("Loading branch..."),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// Time tile widget (responsive, overflow-safe)
// =====================================================
class _TimeTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TimeTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Keep previous API (returns Expanded so callers remain unchanged)
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
          final isNarrow = maxW < 150;

          final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
          final timeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: isNarrow ? 15 : 17);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.95), child: Icon(icon, size: 18, color: Colors.white)),
              const SizedBox(width: 12),

              // Middle column — flexible so it can shrink
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    // Time text inside FittedBox to avoid overflow
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: timeStyle),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
