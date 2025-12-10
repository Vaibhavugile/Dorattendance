// lib/admin/users_admin.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'user_detail.dart';

/// UsersAdmin (READ-ONLY view with attendance dot + counts + animations)
/// - Search users by name/email
/// - Filter users by branch (dropdown)
/// - Shows blue/red dot + today's check-in time
/// - Displays live Present / Absent counts at the top
/// - Animated dot transitions + shimmer-like placeholders
class UsersAdmin extends StatefulWidget {
  const UsersAdmin({Key? key}) : super(key: key);

  @override
  State<UsersAdmin> createState() => _UsersAdminState();
}

class _UsersAdminState extends State<UsersAdmin> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final TextEditingController _searchCtl = TextEditingController();
  String _search = '';
  String? _selectedBranchId;

  late final AnimationController _entranceController;

  // Present / Absent counts
  int _presentCount = 0;
  int _absentCount = 0;
  bool _countsLoading = false;

  // simple guard to avoid racing multiple compute tasks
  Object? _countsToken;

  // CACHE: today's attendance docs for users visible in current list
  final Map<String, DocumentSnapshot> _todayAttendanceCache = {};

  // Subscription to the users query used for counts computation
  StreamSubscription<QuerySnapshot>? _usersSub;
  // last seen user id list to avoid recompute if unchanged
  List<String> _lastUserIds = [];

  Timer? _countsDebounceTimer;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _entranceController.forward();
    _searchCtl.addListener(() => setState(() => _search = _searchCtl.text.trim()));

    // initial subscription
    _subscribeToUsers();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _searchCtl.dispose();
    _usersSub?.cancel();
    _countsDebounceTimer?.cancel();
    super.dispose();
  }

  Query _usersQuery() {
    Query q = _db.collection('users').orderBy('name');
    if (_selectedBranchId != null && _selectedBranchId!.isNotEmpty) {
      q = q.where('branchId', isEqualTo: _selectedBranchId);
    }
    return q;
  }

  String _todayDocId() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String _formatTimeOnly(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat.jm().format(ts.toDate().toLocal());
  }

  // Subscribe to the users query (so we compute counts outside build)
  void _subscribeToUsers() {
    _usersSub?.cancel();
    _usersSub = _usersQuery().snapshots().listen((snap) {
      final docs = snap.docs;
      final uids = docs.map((d) => d.id).toList();

      // If user list didn't change, don't recompute (prevents loops)
      final same = _listsEqual(uids, _lastUserIds);
      if (!same) {
        _lastUserIds = uids;
        _computeCounts(docs);
      }
    }, onError: (e) {
      // On error reset counts
      if (mounted) {
        setState(() {
          _presentCount = 0;
          _absentCount = 0;
          _countsLoading = false;
        });
      }
    });
  }

  // utility to compare lists quickly
  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Compute present/absent counts for given user docs.
  /// Performs parallel reads of users/{uid}/attendance/{today}
  /// Debounced to avoid bursts.
  Future<void> _computeCounts(List<QueryDocumentSnapshot> users) async {
    _countsDebounceTimer?.cancel();
    _countsDebounceTimer = Timer(const Duration(milliseconds: 100), () => _doComputeCounts(users));
  }

  Future<void> _doComputeCounts(List<QueryDocumentSnapshot> users) async {
    final token = Object();
    _countsToken = token;
    if (mounted) {
      setState(() {
        _countsLoading = true;
      });
    }

    try {
      final todayId = _todayDocId();
      final uids = users.map((u) => u.id).toSet().toList();

      // parallel reads
      final futures = uids.map((uid) => _db.collection('users').doc(uid).collection('attendance').doc(todayId).get()).toList();
      final snaps = await Future.wait(futures);

      if (!mounted || _countsToken != token) return;

      int present = 0;
      int absent = 0;
      for (int i = 0; i < uids.length; i++) {
        final uid = uids[i];
        final ds = snaps[i];
        _todayAttendanceCache[uid] = ds; // cache
        if (ds.exists) {
          final m = ds.data() as Map<String, dynamic>? ?? {};
          if (m['checkIn'] != null) {
            present++;
          } else {
            absent++;
          }
        } else {
          absent++;
        }
      }

      if (!mounted) return;
      setState(() {
        _presentCount = present;
        _absentCount = absent;
        _countsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _presentCount = 0;
        _absentCount = users.length;
        _countsLoading = false;
      });
    }
  }

  Widget _headerCard(BuildContext c) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
      axisAlignment: -1,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(c).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.shade400, Colors.purple.shade300]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: const Icon(Icons.people_alt, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Team members', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Search, filter by branch, and see today attendance at a glance', style: Theme.of(c).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _searchCtl.clear();
                  _selectedBranchId = null;
                  // when filter cleared re-subscribe to refresh counts for all users
                  _subscribeToUsers();
                }),
                icon: const Icon(Icons.refresh),
                tooltip: 'Clear filters',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countsBar(BuildContext c) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(c).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26.withOpacity(0.06), blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          // Present
          _countsLoading ? _shimmerCounter(width: 90, height: 34) : _countTile(title: 'Present', count: _presentCount, color: Colors.blueAccent),
          const SizedBox(width: 12),
          _countsLoading ? _shimmerCounter(width: 90, height: 34) : _countTile(title: 'Absent', count: _absentCount, color: Colors.redAccent),
          const Spacer(),
          Text('Today', style: Theme.of(c).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _countTile({required String title, required int count, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
              const SizedBox(height: 2),
              Text(title, style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shimmerCounter({double width = 80, double height = 28}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.2, end: 0.8),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, v, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(v * 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  Widget _searchAndFilter(BuildContext c, List<QueryDocumentSnapshot> branches) {
    // Deduplicate branch IDs and keep stable order
    final seen = <String>{};
    final uniqueBranches = <QueryDocumentSnapshot>[];
    for (final b in branches) {
      if (!seen.contains(b.id)) {
        seen.add(b.id);
        uniqueBranches.add(b);
      }
    }

    final branchItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('All branches')),
      ...uniqueBranches.map((b) {
        final name = (b.data() as Map<String, dynamic>?)?['name'] ?? b.id;
        return DropdownMenuItem<String?>(value: b.id, child: Text(name));
      })
    ];

    final hasSelected = _selectedBranchId == null || seen.contains(_selectedBranchId);
    final currentValue = hasSelected ? _selectedBranchId : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtl,
                decoration: const InputDecoration(
                  hintText: 'Search by name or email...',
                  border: InputBorder.none,
                  icon: Icon(Icons.search),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: DropdownButtonFormField<String?>(
                value: currentValue,
                items: branchItems,
                onChanged: (v) => setState(() {
                  _selectedBranchId = v;
                  // re-subscribe to users query filtered by the new branch
                  _subscribeToUsers();
                }),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Filter by branch'),
                isExpanded: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceIndicator({required bool checkedIn, required String label}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, anim) {
        return ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child));
      },
      child: Row(
        key: ValueKey<bool>(checkedIn),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: checkedIn ? Colors.blueAccent : Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardShimmerPlaceholder(BuildContext c) {
    return Material(
      color: Theme.of(c).colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.2, end: 0.7),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, __) {
                return CircleAvatar(radius: 30, backgroundColor: Colors.grey.withOpacity(v));
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 120, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.18), borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 160, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.12), borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 10),
                  Container(height: 22, width: 100, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.10), borderRadius: BorderRadius.circular(12))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 86, height: 20, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.12), borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _userCard(BuildContext c, QueryDocumentSnapshot doc, int index) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final name = (data['name'] as String?) ?? '';
    final email = (data['email'] as String?) ?? '';
    final photo = (data['photoUrl'] as String?);
    final branchName = (data['branchName'] as String?) ?? '—';

    final uid = doc.id;
    final todayId = _todayDocId();

    // Try cache first
    final cached = _todayAttendanceCache[uid];

    Widget attendanceWidget;
    if (cached == null) {
      attendanceWidget = Container(
        width: 86,
        height: 20,
        alignment: Alignment.center,
        child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
      // background fetch to fill cache
      _db.collection('users').doc(uid).collection('attendance').doc(todayId).get().then((ds) {
        _todayAttendanceCache[uid] = ds;
        if (mounted) setState(() {});
      }).catchError((_) {});
    } else {
      if (!cached.exists) {
        attendanceWidget = _attendanceIndicator(checkedIn: false, label: 'Not checked in');
      } else {
        final m = cached.data() as Map<String, dynamic>? ?? {};
        final checkInTs = m['checkIn'] as Timestamp?;
        if (checkInTs == null) {
          attendanceWidget = _attendanceIndicator(checkedIn: false, label: 'Not checked in');
        } else {
          final checkInLabel = _formatTimeOnly(checkInTs);
          attendanceWidget = _attendanceIndicator(checkedIn: true, label: checkInLabel);
        }
      }
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 420 + (index % 6) * 50),
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
        );
      },
      child: Material(
        color: Theme.of(c).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserDetailPage(uid: uid),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: (photo != null) ? NetworkImage(photo) : null,
                  backgroundColor: Colors.indigo,
                  child: photo == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 18)) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isNotEmpty ? name : email, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(email, style: Theme.of(c).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(branchName),
                        backgroundColor: Colors.white.withOpacity(0.06),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: attendanceWidget,
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesStream = _db.collection('branches').orderBy('name').snapshots();
    final usersQuery = _usersQuery();

    return RefreshIndicator(
      onRefresh: () async {
        _todayAttendanceCache.clear();
        _lastUserIds = [];
        _usersSub?.cancel();
        _subscribeToUsers();
        await Future.delayed(const Duration(milliseconds: 250));
      },
      // Single scrollable area containing header + counts + search + user list
      child: CustomScrollView(
        slivers: [
          // Header card (scrolls away)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: _headerCard(context),
          )),
          // Counts bar
          SliverToBoxAdapter(child: _countsBar(context)),
          // Search & Filter (depends on branches stream)
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: branchesStream,
              builder: (ctx, branchSnap) {
                final branches = branchSnap.hasData ? branchSnap.data!.docs : <QueryDocumentSnapshot>[];
                return _searchAndFilter(context, branches.cast<QueryDocumentSnapshot>());
              },
            ),
          ),
          SliverToBoxAdapter(child: const SizedBox(height: 6)),

          // Users stream - returns different slivers depending on state
          StreamBuilder<QuerySnapshot>(
            stream: usersQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return SliverToBoxAdapter(
                  child: Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: Text('Error: ${snap.error}'),
                  ),
                );
              }

              if (!snap.hasData) {
                // Loading placeholders (shimmer cards)
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (c, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
                      child: _cardShimmerPlaceholder(context),
                    ),
                    childCount: 6,
                  ),
                );
              }

              final allDocs = snap.data!.docs;
              final filtered = allDocs.where((d) {
                if (_search.isEmpty) return true;
                final m = d.data() as Map<String, dynamic>? ?? {};
                final name = (m['name'] ?? '').toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                return name.contains(_search.toLowerCase()) || email.contains(_search.toLowerCase());
              }).toList();

              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_off, size: 84, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        Text('No staff found', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text('Try removing filters or add staff from the admin panel', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              }

              // Real user list
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) {
                    final doc = filtered[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                      child: _userCard(context, doc, i),
                    );
                  },
                  childCount: filtered.length,
                ),
              );
            },
          ),
          // Add some bottom padding so last item isn't flush to the bottom edge
          SliverToBoxAdapter(child: const SizedBox(height: 20)),
        ],
      ),
    );
  }
}
