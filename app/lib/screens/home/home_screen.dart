// Home screen — four tab navigation: Home, Profiles, Automations, Admin

import 'package:flutter/material.dart';
import '../profiles/profiles_screen.dart';
import '../automations/automations_screen.dart';
import '../admin/admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    _DashboardTab(),
    ProfilesScreen(),
    AutomationsScreen(),
    AdminScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF111111),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white38,
        selectedLabelStyle: const TextStyle(letterSpacing: 2, fontSize: 10),
        unselectedLabelStyle: const TextStyle(letterSpacing: 2, fontSize: 10),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'PROFILES',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt_outlined),
            activeIcon: Icon(Icons.bolt),
            label: 'AUTOMATIONS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'ADMIN',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AURA',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w200,
                letterSpacing: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Summer Ridge',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white38,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),
            // Mirror status card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aura Mirror 1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Online · 192.168.0.200',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 4,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'No recent activity',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
