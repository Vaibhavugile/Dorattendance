import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersAdmin extends StatefulWidget {
  const UsersAdmin({Key? key}) : super(key: key);

  @override
  State<UsersAdmin> createState() => _UsersAdminState();
}

class _UsersAdminState extends State<UsersAdmin> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _search = '';

  Future<void> _toggleManager(String uid, bool makeManager) async {
    try {
      await _db.collection('users').doc(uid).update({'role': makeManager ? 'manager' : 'staff'});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _deleteUserDoc(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user doc?'),
        content: const Text('Only the Firestore user document will be removed; Firebase Auth user remains. Use console to remove auth account.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    try {
      await _db.collection('users').doc(uid).delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User doc deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or email'),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('users').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs.where((d) {
                if (_search.isEmpty) return true;
                final m = d.data() as Map<String, dynamic>;
                final name = (m['name'] ?? '').toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                return name.contains(_search) || email.contains(_search);
              }).toList();

              if (docs.isEmpty) return const Center(child: Text('No users match'));

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final m = d.data() as Map<String, dynamic>;
                  final role = (m['role'] ?? 'staff') as String;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: ListTile(
                      tileColor: Theme.of(context).colorScheme.surfaceVariant,
                      leading: CircleAvatar(child: Text((m['name'] ?? '?')[0] ?? '?')),
                      title: Text(m['name'] ?? 'No name'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['email'] ?? ''),
                          if (m['branchName'] != null)
                            Text('Branch: ${m['branchName']}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButton<String>(
                            value: role,
                            items: const [
                              DropdownMenuItem(value: 'staff', child: Text('Staff')),
                              DropdownMenuItem(value: 'manager', child: Text('Manager')),
                            ],
                            onChanged: (v) => _toggleManager(d.id, v == 'manager'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteUserDoc(d.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        )
      ],
    );
  }
}
