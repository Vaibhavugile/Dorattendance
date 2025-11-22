import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BranchesAdmin extends StatefulWidget {
  const BranchesAdmin({Key? key}) : super(key: key);

  @override
  State<BranchesAdmin> createState() => _BranchesAdminState();
}

class _BranchesAdminState extends State<BranchesAdmin> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _latC = TextEditingController();
  final _lngC = TextEditingController();
  bool _saving = false;

  Future<void> _saveBranch([String? docId]) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _nameC.text.trim();
    final lat = double.tryParse(_latC.text.trim());
    final lng = double.tryParse(_lngC.text.trim());
    try {
      final data = {'name': name, 'lat': lat, 'lng': lng};
      if (docId == null) {
        await _db.collection('branches').add(data);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch added')));
      } else {
        await _db.collection('branches').doc(docId).update(data);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch updated')));
      }
      _nameC.clear(); _latC.clear(); _lngC.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  void _populateForm(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    _nameC.text = m['name'] ?? '';
    _latC.text = (m['lat'] ?? '').toString();
    _lngC.text = (m['lng'] ?? '').toString();
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _branchForm(docId: doc.id),
      );
    });
  }

  Widget _branchForm({String? docId}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: _nameC, decoration: const InputDecoration(labelText: 'Branch name'), validator: (v) => v==null||v.isEmpty? 'Required':null),
            TextFormField(controller: _latC, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v)=> double.tryParse(v ?? '')==null? 'Enter valid number':null),
            TextFormField(controller: _lngC, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: TextInputType.numberWithOptions(decimal: true), validator: (v)=> double.tryParse(v ?? '')==null? 'Enter valid number':null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton(onPressed: _saving? null: () => _saveBranch(docId), child: Text(docId==null? 'Create Branch':'Update Branch'))),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () { _nameC.clear(); _latC.clear(); _lngC.clear(); Navigator.of(context).pop(); }, child: const Text('Cancel'))
            ])
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String docId) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete branch?'), content: const Text('This will remove the branch from database.'), actions: [TextButton(onPressed: ()=>Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton(onPressed: ()=>Navigator.of(context).pop(true), child: const Text('Delete'))]));
    if (ok == true) {
      try {
        await _db.collection('branches').doc(docId).delete();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branch deleted')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.add_business),
              title: const Text('Create new branch'),
              subtitle: const Text('Add branch name and coordinates'),
              trailing: ElevatedButton.icon(onPressed: (){ showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) { return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: _branchForm()); }); }, icon: const Icon(Icons.add), label: const Text('Add')),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('branches').orderBy('name').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No branches yet'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data() as Map<String, dynamic>;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        tileColor: Theme.of(context).colorScheme.surfaceVariant,
                        title: Text(m['name'] ?? d.id),
                        subtitle: Text('lat: ${m['lat']}, lng: ${m['lng']}'),
                        leading: CircleAvatar(child: Text((m['name'] ?? '?')[0] ?? '?')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit), onPressed: () { _populateForm(d); }),
                          IconButton(icon: const Icon(Icons.delete), onPressed: () => _confirmDelete(d.id)),
                        ]),
                      ),
                    );
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
