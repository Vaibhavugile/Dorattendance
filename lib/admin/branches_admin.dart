import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Upgraded BranchesAdmin
/// Features:
///  - Animated, modern card UI
///  - Create / Edit / Delete branches with validation
///  - "Use my location" button fills lat/lng via Geolocator
///  - Add / edit `radiusMeters` per-branch (defaults to 1000m)
///  - Empty / loading / error states
///  - Smooth modal bottom sheet form and confirmations
class BranchesAdmin extends StatefulWidget {
  const BranchesAdmin({Key? key}) : super(key: key);

  @override
  State<BranchesAdmin> createState() => _BranchesAdminState();
}

class _BranchesAdminState extends State<BranchesAdmin> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // animations
  late final AnimationController _entranceController;
  late final Animation<double> _fadeIn;

  // default radius used when creating a branch or when branch doc doesn't include radiusMeters
  static const int _defaultRadiusMeters = 1000;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Location services are disabled. Please enable them.';
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw 'Location permission denied.';
    }
    if (permission == LocationPermission.deniedForever) throw 'Location permission permanently denied. Enable it from settings.';
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
  }

  String _formatRadiusDisplay(int meters) {
    if (meters % 1000 == 0) {
      return '${meters ~/ 1000} km';
    } else if (meters >= 1000) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    } else {
      return '$meters m';
    }
  }

  Future<void> _showBranchForm({DocumentSnapshot? editing}) async {
    final isEditing = editing != null;
    final Map<String, dynamic>? editingData = editing?.data() as Map<String, dynamic>?;
    final nameCtrl = TextEditingController(text: editingData?['name'] as String? ?? '');
    final addrCtrl = TextEditingController(text: editingData?['address'] as String? ?? '');
    final latCtrl = TextEditingController(text: (editingData?['lat'] != null) ? editingData!['lat'].toString() : '');
    final lngCtrl = TextEditingController(text: (editingData?['lng'] != null) ? editingData!['lng'].toString() : '');

    // radius controller (meters) — if editing and value present, show it; otherwise default empty to let user decide
    final radiusInitial = (editingData != null && editingData.containsKey('radiusMeters'))
        ? (editingData!['radiusMeters']?.toString() ?? _defaultRadiusMeters.toString())
        : _defaultRadiusMeters.toString();
    final radiusCtrl = TextEditingController(text: radiusInitial);

    final formKey = GlobalKey<FormState>();
    bool loadingLocation = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0,8))],
            ),
            child: StatefulBuilder(builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(isEditing ? 'Edit branch' : 'Create branch', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close))
                    ],
                  ),
                  const SizedBox(height: 6),
                  Form(
                    key: formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Branch name', prefixIcon: Icon(Icons.store)),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter branch name' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: addrCtrl,
                          decoration: const InputDecoration(labelText: 'Address (optional)', prefixIcon: Icon(Icons.location_on)),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: latCtrl,
                                decoration: const InputDecoration(labelText: 'Latitude', prefixIcon: Icon(Icons.my_location)),
                                keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Provide lat or use my location';
                                  final n = double.tryParse(v);
                                  if (n == null) return 'Invalid latitude';
                                  if (n < -90 || n > 90) return 'Latitude out of range';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: lngCtrl,
                                decoration: const InputDecoration(labelText: 'Longitude', prefixIcon: Icon(Icons.explore)),
                                keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Provide lng or use my location';
                                  final n = double.tryParse(v);
                                  if (n == null) return 'Invalid longitude';
                                  if (n < -180 || n > 180) return 'Longitude out of range';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Radius input (in meters)
                        TextFormField(
                          controller: radiusCtrl,
                          decoration: InputDecoration(
                            labelText: 'Allowed radius (meters)',
                            hintText: 'e.g. 1000',
                            prefixIcon: const Icon(Icons.circle_outlined),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Provide radius in meters';
                            final n = int.tryParse(v.replaceAll(',', '').trim());
                            if (n == null) return 'Invalid number';
                            if (n <= 0) return 'Radius must be positive';
                            if (n > 100000) return 'Radius too large';
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // ---------- SAFER HORIZONTAL LAYOUT: make primary button flexible ----------
                        Row(
                          children: [
                            // Let the main action take available space so it can shrink gracefully
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: loadingLocation ? null : () async {
                                  setModalState(() { loadingLocation = true; });
                                  try {
                                    final pos = await _getCurrentPosition();
                                    latCtrl.text = pos.latitude.toStringAsFixed(6);
                                    lngCtrl.text = pos.longitude.toStringAsFixed(6);
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                  } finally {
                                    setModalState(() { loadingLocation = false; });
                                  }
                                },
                                icon: const Icon(Icons.my_location),
                                label: Text(loadingLocation ? 'Locating...' : 'Use my location'),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Keep the secondary action compact
                            SizedBox(
                              height: 48, // match typical button height to align nicely
                              child: TextButton(
                                onPressed: () {
                                  latCtrl.clear();
                                  lngCtrl.clear();
                                },
                                child: const Text('Clear'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Save/create row already used Expanded so it will fill width correctly
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;

                                  final parsedRadius = int.tryParse(radiusCtrl.text.replaceAll(',', '').trim()) ?? _defaultRadiusMeters;

                                  final data = {
                                    'name': nameCtrl.text.trim(),
                                    'address': addrCtrl.text.trim(),
                                    'lat': double.parse(latCtrl.text.trim()),
                                    'lng': double.parse(lngCtrl.text.trim()),
                                    'radiusMeters': parsedRadius,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  try {
                                    if (isEditing) {
                                      await _db.collection('branches').doc(editing!.id).update(data);
                                    } else {
                                      data['createdAt'] = FieldValue.serverTimestamp();
                                      await _db.collection('branches').add(data);
                                    }
                                    Navigator.of(ctx).pop();
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEditing ? 'Branch updated' : 'Branch created')));
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                                  }
                                },
                                child: Text(isEditing ? 'Save changes' : 'Create branch'),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  Future<void> _deleteBranch(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete branch?'),
        content: Text('Delete branch "${doc['name']}" and all its associated data? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.collection('branches').doc(doc.id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch removed')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('No branches yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Create your first store branch and workers will be able to select it at signup.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => _showBranchForm(), icon: const Icon(Icons.add), label: const Text('Create branch')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('branches').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading branches: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 200));
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              itemCount: docs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      title: const Text('Branches', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Manage store locations'),
                      trailing: FilledButton.icon(onPressed: () => _showBranchForm(), icon: const Icon(Icons.add), label: const Text('Add')),
                    ),
                  );
                }

                final doc = docs[index - 1];
                final data = doc.data() as Map<String, dynamic>;
                final name = data['name'] as String? ?? 'Unnamed';
                final addr = data['address'] as String? ?? '';
                final lat = data['lat'];
                final lng = data['lng'];
                final radius = (data.containsKey('radiusMeters') && data['radiusMeters'] != null)
                    ? (data['radiusMeters'] is num ? (data['radiusMeters'] as num).toInt() : int.tryParse(data['radiusMeters'].toString()) ?? _defaultRadiusMeters)
                    : _defaultRadiusMeters;

                return Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${addr.isNotEmpty ? '$addr\n' : ''}(${lat?.toStringAsFixed(6) ?? '-'}, ${lng?.toStringAsFixed(6) ?? '-'})\nRadius: ${_formatRadiusDisplay(radius)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    leading: CircleAvatar(child: const Icon(Icons.store)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          onPressed: () => _showBranchForm(editing: doc),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => _deleteBranch(doc),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    onTap: () {
                      showDialog(context: context, builder: (ctx) {
                        return AlertDialog(
                          title: Text(name),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (addr.isNotEmpty) Text(addr),
                              const SizedBox(height: 8),
                              Text('Latitude: ${lat?.toStringAsFixed(6) ?? '-'}'),
                              Text('Longitude: ${lng?.toStringAsFixed(6) ?? '-'}'),
                              const SizedBox(height: 8),
                              Text('Allowed radius: ${_formatRadiusDisplay(radius)}'),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                            FilledButton(onPressed: () {
                              Navigator.of(ctx).pop();
                              _showBranchForm(editing: doc);
                            }, child: const Text('Edit')),
                          ],
                        );
                      });
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
