// Profiles screen — manage people and their vehicles

import 'package:flutter/material.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PROFILES',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 4,
                    color: Colors.white38,
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'No profiles yet',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
