import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'branches_admin.dart';
import 'users_admin.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _picker = ImagePicker();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  bool _uploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadProfile(String uid) async {
    try {
      final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;

      await _uploadFile(uid, File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Image pick failed: $e')));
      }
    }
  }

  Future<void> _takePhotoAndUpload(String uid) async {
    try {
      final XFile? picked = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 80, maxWidth: 1200);
      if (picked == null) return;

      await _uploadFile(uid, File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Camera failed: $e')));
      }
    }
  }

  Future<void> _uploadFile(String uid, File file) async {
    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final fileName = "profile_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final ref = _storage.ref().child("users/$uid/$fileName");

      final task = ref.putFile(file);

      task.snapshotEvents.listen((event) {
        setState(() {
          _uploadProgress = event.bytesTransferred / event.totalBytes;
        });
      });

      final snap = await task;
      final url = await snap.ref.getDownloadURL();

      await _db.collection("users").doc(uid).update({"photoUrl": url});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile updated successfully")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Upload failed: $e")));
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

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("DOR — Admin Dashboard"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: Column(
        children: [
          // TOP PROFILE CARD ───────────────────────────────────────────────
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('users').doc(uid).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                );
              }

              final data = snap.data!.data() as Map<String, dynamic>?;

              final name = data?["name"] ?? user.displayName ?? "Admin";
              final photoUrl = data?["photoUrl"];

              return AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final action = await showModalBottomSheet<int>(
                          context: context,
                          builder: (_) => SafeArea(
                            child: Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.photo_library),
                                  title: const Text("Choose from Gallery"),
                                  onTap: () => Navigator.pop(context, 0),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text("Take Photo"),
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

                        if (action == 0) await _pickAndUploadProfile(uid);
                        if (action == 1) await _takePhotoAndUpload(uid);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.indigo,
                            backgroundImage:
                                photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: photoUrl == null
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 22, color: Colors.white),
                                  )
                                : null,
                          ),
                          if (_uploading)
                            SizedBox(
                              width: 72,
                              height: 72,
                              child: CircularProgressIndicator(
                                value: _uploadProgress,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Welcome, $name",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  ],
                ),
              );
            },
          ),

          // TABS ─────────────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: "Branches"),
                Tab(text: "Users"),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // TAB CONTENT ───────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                BranchesAdmin(),
                UsersAdmin(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
