import 'package:flutter/material.dart';

/// The signed-in shell. Projects (#4) and tasks (#5) replace the body.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.email, required this.onLogout});

  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فراش'),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'حساب',
            icon: const Icon(Icons.account_circle_outlined),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: false,
                child: Text(email, textDirection: TextDirection.ltr),
              ),
              PopupMenuItem<void>(
                onTap: onLogout,
                child: const ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('خروج'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: const Center(child: Text('به فراش خوش آمدید')),
    );
  }
}
