import 'package:flutter/material.dart';

import 'profile_body.dart';

/// Standalone deep-link route (`/profile`) for the user profile. Wraps
/// [ProfileBody] in its own Scaffold + AppBar; the same body also serves the
/// Profile tab inside [RoleShellScreen].
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const ProfileBody(),
    );
  }
}
