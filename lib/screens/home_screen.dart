// lib/screens/home_screen.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

      // listen for progress
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.totalBytes > 0 ? snapshot.bytesTransferred / snapshot.totalBytes : 0.0;
        if (mounted) setState(() => _uploadProgress = progress);
      });

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      // Save URL to users/{uid} doc
      await _db.collection('users').doc(uid).update({'photoUrl': url});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() {
        _uploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  // DEBUG helper: upload the file you previously uploaded to the environment.
  // Path (from your uploaded screenshot) is:
  // /mnt/data/WhatsApp Image 2025-11-22 at 18.56.50_b7643f47.jpg
  // This is meant for local/emulator/dev only.
  Future<void> uploadTestImageFromLocalPath(String uid) async {
    if (!kDebugMode) return;
    final testPath = '/mnt/data/WhatsApp Image 2025-11-22 at 18.56.50_b7643f47.jpg';
    final f = File(testPath);
    if (!await f.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test image not found at $testPath')));
      return;
    }
    await _uploadFileAndSaveUrl(uid, f);
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
        actions: [
          IconButton(onPressed: () => auth.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 22),
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: userDocStream,
                builder: (context, snapshot) {
                  String? photoUrl;
                  String displayName = user.displayName ?? user.email ?? 'Staff';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final m = snapshot.data!.data() as Map<String, dynamic>?;
                    photoUrl = m?['photoUrl'] as String?;
                    displayName = (m?['name'] as String?) ?? displayName;
                  }

                  return Hero(
                    tag: 'greeting-card',
                    child: Material(
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
                                // show options
                                final choice = await showModalBottomSheet<int>(
                                  context: context,
                                  builder: (_) => SafeArea(
                                    child: Wrap(
                                      children: [
                                        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.of(context).pop(0)),
                                        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take a photo'), onTap: () => Navigator.of(context).pop(1)),
                                        if (kDebugMode) ListTile(leading: const Icon(Icons.file_copy), title: const Text('Upload test image (debug)'), onTap: () => Navigator.of(context).pop(2)),
                                        ListTile(leading: const Icon(Icons.close), title: const Text('Cancel'), onTap: () => Navigator.of(context).pop(-1)),
                                      ],
                                    ),
                                  ),
                                );

                                if (choice == 0) {
                                  await _pickAndUploadProfile(uid);
                                } else if (choice == 1) {
                                  await _takePhotoAndUpload(uid);
                                } else if (choice == 2) {
                                  await uploadTestImageFromLocalPath(uid);
                                }
                              },
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 34,
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    backgroundImage: (photoUrl != null) ? NetworkImage(photoUrl) as ImageProvider : null,
                                    child: (photoUrl == null)
                                        ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 20, color: Colors.white))
                                        : null,
                                  ),
                                  if (_uploading)
                                    SizedBox(
                                      width: 68,
                                      height: 68,
                                      child: CircularProgressIndicator(value: _uploadProgress),
                                    )
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
                                ],
                              ),
                            ),
                            StreamBuilder<DocumentSnapshot>(
                              stream: todayDocStream,
                              builder: (context, snap) {
                                if (!snap.hasData || !snap.data!.exists) {
                                  return Chip(label: Text('No record'), backgroundColor: Colors.grey.shade800);
                                }
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
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              // The rest of the screen (times & check in/out) — for brevity you can reuse your previous implementation,
              // but we'll display the times below as before; refer to your existing logic to keep behavior consistent.
              // ... (keep your existing attendance UI) ...
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: todayDocStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final doc = snapshot.data!;
                    final data = doc.exists ? (doc.data() as Map<String, dynamic>?) : null;
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
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: hasIn ? null : () => _doCheckIn(uid),
                                icon: const Icon(Icons.login),
                                label: Text(hasIn ? 'Checked In' : 'Check In'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: hasIn && !hasOut ? () => _doCheckOut(uid) : null,
                                icon: const Icon(Icons.logout),
                                label: Text(hasIn ? (hasOut ? 'Checked Out' : 'Check Out') : 'Check Out'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Keep your existing check in/out functions (copied from previous HomeScreen)
  Future<void> _doCheckIn(String uid) async {
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) {
          final data = snap.data()!;
          if (data['checkIn'] != null) {
            throw ('Already checked in');
          } else {
            tx.update(docRef, {'checkIn': FieldValue.serverTimestamp()});
          }
        } else {
          tx.set(docRef, {
            'date': _docIdForToday(),
            'checkIn': FieldValue.serverTimestamp(),
            'checkOut': null,
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked in — have a great shift!')));
    } catch (e) {
      if (!mounted) return;
      final msg = (e is String) ? e : 'Check-in failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _doCheckOut(String uid) async {
    final docRef = _db.collection('users').doc(uid).collection('attendance').doc(_docIdForToday());

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          throw ('No check-in found for today');
        }
        final data = snap.data()!;
        if (data['checkIn'] == null) throw ('You have not checked in today');
        if (data['checkOut'] != null) throw ('Already checked out');
        tx.update(docRef, {'checkOut': FieldValue.serverTimestamp()});
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked out — good work!')));
    } catch (e) {
      if (!mounted) return;
      final msg = (e is String) ? e : 'Check-out failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
