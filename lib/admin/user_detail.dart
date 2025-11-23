// lib/admin/user_detail.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Redesigned UserDetailPage with:
/// - From/To range selection
/// - Present / Absent counts for range
/// - Full scrollable attendance table (descending)
/// - Segmented control to filter: All / Present / Absent
/// - Defensive layout changes to avoid overflow errors
class UserDetailPage extends StatefulWidget {
  final String uid;
  const UserDetailPage({Key? key, required this.uid}) : super(key: key);

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

enum AttendanceFilter { all, present, absent }

class _UserDetailPageState extends State<UserDetailPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // user doc
  Map<String, dynamic>? _userDoc;
  bool _loadingUser = true;
  String? _userLoadError;

  // range selectors (default: current calendar week Mon..Sun)
  late DateTime _from;
  late DateTime _to;

  // attendance data
  StreamSubscription<QuerySnapshot>? _attendanceSub;
  final Map<String, Map<String, dynamic>> _attendanceByDate = {}; // key yyyy-MM-dd
  bool _loadingAttendanceRange = true;
  String? _attendanceRangeError;

  // UI
  late final AnimationController _animController;
  DateTime? _selectedRowDate;
  AttendanceFilter _filter = AttendanceFilter.all;

  // counts
  int _presentCount = 0;
  int _absentCount = 0;

  // scroll
  final ScrollController _historyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final weekday = now.weekday; // Monday=1
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    _from = startOfWeek;
    _to = endOfWeek;

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _animController.forward();

    _loadUser();
    _subscribeAttendanceRange();
  }

  @override
  void dispose() {
    _attendanceSub?.cancel();
    _animController.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  // Helpers
  String _docIdForDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _formatDateLong(DateTime d) => DateFormat.yMMMMEEEEd().format(d);
  String _formatDateShort(DateTime d) => DateFormat('dd MMM EEE').format(d);
  String _formatTime(Timestamp? ts) {
    if (ts == null) return '—';
    return DateFormat.jm().format(ts.toDate().toLocal());
  }

  String _durationLabel(Timestamp? inTs, Timestamp? outTs) {
    if (inTs == null || outTs == null) return '—';
    final dur = outTs.toDate().difference(inTs.toDate());
    final hours = dur.inHours;
    final minutes = dur.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Future<void> _loadUser() async {
    setState(() {
      _loadingUser = true;
      _userLoadError = null;
    });
    try {
      final snap = await _db.collection('users').doc(widget.uid).get();
      if (!snap.exists) {
        setState(() {
          _userLoadError = 'User not found';
        });
        return;
      }
      _userDoc = snap.data();
    } catch (e) {
      setState(() => _userLoadError = 'Failed to load user: $e');
    } finally {
      setState(() => _loadingUser = false);
    }
  }

  void _subscribeAttendanceRange() {
    _attendanceSub?.cancel();
    setState(() {
      _loadingAttendanceRange = true;
      _attendanceRangeError = null;
      _attendanceByDate.clear();
      _presentCount = 0;
      _absentCount = 0;
      _selectedRowDate = null;
    });

    final fromId = _docIdForDate(_from);
    final toId = _docIdForDate(_to);

    final query = _db
        .collection('users')
        .doc(widget.uid)
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: fromId)
        .where('date', isLessThanOrEqualTo: toId)
        .orderBy('date', descending: true);

    _attendanceSub = query.snapshots().listen((snap) {
      _attendanceByDate.clear();
      for (final d in snap.docs) {
        final m = (d.data() as Map<String, dynamic>?) ?? {};
        final dateStr = (m['date'] as String?) ?? d.id;
        _attendanceByDate[dateStr] = m;
      }
      _recomputeCounts();
      setState(() {
        _loadingAttendanceRange = false;
      });
    }, onError: (e) {
      setState(() {
        _loadingAttendanceRange = false;
        _attendanceRangeError = 'Failed to load attendance: $e';
        _attendanceByDate.clear();
      });
    });
  }

  void _recomputeCounts() {
    final days = _daysInRange(_from, _to);
    int present = 0, absent = 0;
    for (final d in days) {
      final id = _docIdForDate(d);
      final m = _attendanceByDate[id];
      if (m != null && (m['checkIn'] != null)) present++; else absent++;
    }
    setState(() {
      _presentCount = present;
      _absentCount = absent;
    });
  }

  List<DateTime> _daysInRange(DateTime a, DateTime b) {
    final start = DateTime(a.year, a.month, a.day);
    final end = DateTime(b.year, b.month, b.day);
    final list = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      list.add(d);
    }
    // descending
    list.sort((x, y) => y.compareTo(x));
    return list;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.year, picked.month, picked.day);
        if (_from.isAfter(_to)) _to = _from;
      });
      _subscribeAttendanceRange();
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _to = DateTime(picked.year, picked.month, picked.day);
        if (_to.isBefore(_from)) _from = _to;
      });
      _subscribeAttendanceRange();
    }
  }

  void _quickPickWeekContaining(DateTime d) {
    final weekday = d.weekday;
    final start = DateTime(d.year, d.month, d.day).subtract(Duration(days: weekday - 1));
    final end = start.add(const Duration(days: 6));
    setState(() {
      _from = start;
      _to = end;
    });
    _subscribeAttendanceRange();
  }

  void _quickPickThisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    setState(() {
      _from = start;
      _to = end;
    });
    _subscribeAttendanceRange();
  }

  Future<void> _onRowTap(DateTime d) async {
    setState(() {
      _selectedRowDate = d;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    if (_historyScroll.hasClients) {
      _historyScroll.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    }
  }

  // --- UI pieces ---

  Widget _header(BuildContext c) {
    final photo = _userDoc?['photoUrl'] as String?;
    final name = (_userDoc?['name'] as String?) ?? (_userDoc?['email'] as String?) ?? 'Staff';
    final branch = (_userDoc?['branchName'] as String?) ?? '-';
    final role = (_userDoc?['role'] as String?) ?? '-';

    return FadeTransition(
      opacity: CurvedAnimation(parent: _animController, curve: Curves.easeOut),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(c).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: (photo != null) ? NetworkImage(photo) : null,
                backgroundColor: Colors.indigo,
                child: photo == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 26)) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.store, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(child: Text(branch, style: Theme.of(c).textTheme.bodySmall)),
                    const SizedBox(width: 12),
                    const Icon(Icons.badge, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(child: Text(role, style: Theme.of(c).textTheme.bodySmall)),
                  ]),
                ]),
              ),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presentAbsentCard(BuildContext c) {
    return Material(
      color: Theme.of(c).colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
        child: Row(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Present', style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(_presentCount.toString(), key: ValueKey<int>(_presentCount), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              ),
            ]),
            const SizedBox(width: 18),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Absent', style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(_absentCount.toString(), key: ValueKey<int>(_absentCount), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ),
            ]),
            const Spacer(),
            // Wrap the range info and quick pick icons in Flexible + FittedBox (prevents overflow)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Range', style: Theme.of(c).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(DateFormat('dd MMM').format(_from), style: Theme.of(c).textTheme.bodySmall),
                    const SizedBox(width: 6),
                    const Icon(Icons.swap_horiz, size: 16),
                    const SizedBox(width: 6),
                    Text(DateFormat('dd MMM').format(_to), style: Theme.of(c).textTheme.bodySmall),
                    const SizedBox(width: 8),
                    // smaller icons to avoid overflow
                    IconButton(onPressed: () => _quickPickWeekContaining(DateTime.now()), icon: const Icon(Icons.calendar_view_week), visualDensity: VisualDensity.compact),
                    IconButton(onPressed: _quickPickThisMonth, icon: const Icon(Icons.calendar_view_month), visualDensity: VisualDensity.compact),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateRangePickers() {
    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _pickFromDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Flexible(child: Text('From: ${DateFormat('MMM d, yyyy').format(_from)}', overflow: TextOverflow.ellipsis)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _pickToDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Flexible(child: Text('To: ${DateFormat('MMM d, yyyy').format(_to)}', overflow: TextOverflow.ellipsis)),
        ),
      ),
    ]);
  }

  Widget _filterSegment() {
    return Row(
      children: [
        const SizedBox(width: 6),
        ToggleButtons(
          isSelected: [
            _filter == AttendanceFilter.all,
            _filter == AttendanceFilter.present,
            _filter == AttendanceFilter.absent,
          ],
          onPressed: (index) {
            setState(() {
              _filter = AttendanceFilter.values[index];
            });
          },
          borderRadius: BorderRadius.circular(8),
          selectedColor: Colors.white,
          fillColor: Theme.of(context).colorScheme.primary,
          constraints: const BoxConstraints(minWidth: 72, minHeight: 36),
          children: const [
            Text('All'),
            Text('Present'),
            Text('Absent'),
          ],
        ),
      ],
    );
  }

  // history table: apply filter here to get filteredDays
  Widget _historyTable() {
    final days = _daysInRange(_from, _to);

    if (_loadingAttendanceRange) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 6),
        controller: _historyScroll,
        itemCount: 8,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (c, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 10),
            child: Row(children: [
              CircleAvatar(radius: 10, backgroundColor: Colors.grey.shade700),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: Container(height: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Container(height: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Container(height: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Container(height: 12, color: Colors.grey.shade700)),
            ]),
          );
        },
      );
    }

    if (_attendanceRangeError != null) {
      return Center(child: Text(_attendanceRangeError!, style: const TextStyle(color: Colors.orangeAccent)));
    }

    // apply filter
    final filteredDays = days.where((d) {
      final id = _docIdForDate(d);
      final m = _attendanceByDate[id];
      final present = (m != null && m['checkIn'] != null);
      if (_filter == AttendanceFilter.present) return present;
      if (_filter == AttendanceFilter.absent) return !present;
      return true;
    }).toList();

    // now build list using filteredDays (correct itemCount)
    return ListView.separated(
      controller: _historyScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filteredDays.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (c, idx) {
        final d = filteredDays[idx];
        final id = _docIdForDate(d);
        final m = _attendanceByDate[id];
        final inTs = m?['checkIn'] as Timestamp?;
        final outTs = m?['checkOut'] as Timestamp?;
        final present = inTs != null;

        final isSelected = _selectedRowDate != null &&
            _selectedRowDate!.year == d.year &&
            _selectedRowDate!.month == d.month &&
            _selectedRowDate!.day == d.day;

        return InkWell(
          onTap: () => _onRowTap(d),
          child: Container(
            color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.06) : null,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 14),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: present ? Colors.blueAccent : Colors.redAccent)),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: Text(_formatDateShort(d), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 3, child: Text(_formatTime(inTs), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                Expanded(flex: 3, child: Text(_formatTime(outTs), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(_durationLabel(inTs, outTs), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- main build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_userDoc?['name'] as String? ?? 'User details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: DateTimeRange(start: _from, end: _to),
              );
              if (picked != null) {
                setState(() {
                  _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
                  _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
                });
                _subscribeAttendanceRange();
              }
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // header
            _loadingUser
                ? Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(height: 86, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 12), child: const SizedBox(height: 6, width: double.infinity, child: LinearProgressIndicator())),
                  )
                : _userLoadError != null
                    ? Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(padding: const EdgeInsets.all(12), child: Text(_userLoadError!)),
                      )
                    : _header(context),
            const SizedBox(height: 12),

            // counts + quick pickers
            _presentAbsentCard(context),
            const SizedBox(height: 12),

            // from/to pickers
            _dateRangePickers(),
            const SizedBox(height: 12),

            // filter segmented control
            _filterSegment(),
            const SizedBox(height: 12),

            // history label + refresh
            Row(
              children: [
                Text('Attendance', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Flexible(child: Text('(${DateFormat('dd MMM yyyy').format(_from)} → ${DateFormat('dd MMM yyyy').format(_to)})', style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                const Spacer(),
                IconButton(onPressed: _subscribeAttendanceRange, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),

            // table header labels
            Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6),
                child: Row(children: [
                  const SizedBox(width: 34),
                  Expanded(flex: 3, child: Text('Date', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text('In', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  Expanded(flex: 3, child: Text('Out', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Duration', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                ]),
              ),
            ),
            const SizedBox(height: 6),

            // Expanded scrollable history table
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: _historyTable(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
