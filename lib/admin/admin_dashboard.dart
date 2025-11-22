import 'package:flutter/material.dart';
import 'branches_admin.dart';
import 'users_admin.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOR — Admin'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [Tab(text: 'Branches'), Tab(text: 'Users')],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          IconButton(onPressed: () { Navigator.of(context).maybePop(); }, icon: const Icon(Icons.close)),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [BranchesAdmin(), UsersAdmin()],
      ),
    );
  }
}
