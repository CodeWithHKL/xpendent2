import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../profile/categories_screen.dart';
import '../profile/personal_info_screen.dart';
import '../profile/currency_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isUploading = false;

  // Custom route builder that smoothly slides the destination page in from the right
  Route _createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); // Slide from right
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _pickAndChangeProfileImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 75,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      await _firestoreService.updateUserProfilePicture(widget.user.uid, base64Image);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update picture: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() => _isUploading = true);
    try {
      await _firestoreService.deleteUserProfilePicture(widget.user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove picture: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _showSignOutConfirmation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF18243E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text(
            'Sign Out',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Are you sure you want to sign out?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      await AuthService().signOut();
    }
  }

  Widget _buildAvatarImage(String? base64Picture) {
    if (base64Picture != null && base64Picture.isNotEmpty) {
      try {
        final bytes = base64Decode(base64Picture);
        return Image.memory(
          bytes,
          width: 108,
          height: 108,
          fit: BoxFit.cover,
        );
      } catch (e) {
        debugPrint('Error decoding base64 avatar: $e');
      }
    }

    return Container(
      width: 108,
      height: 108,
      color: const Color(0xFF1E2D4A),
      child: const Icon(
        Icons.person,
        size: 56,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildProfileAvatar(String? base64Picture) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndChangeProfileImage,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: ClipOval(
              child: _buildAvatarImage(base64Picture),
            ),
          ),
          if (_isUploading)
            const CircularProgressIndicator(color: Colors.white),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF1D61E7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color textColor = Colors.white,
    Color iconColor = Colors.white70,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2642),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(icon, color: iconColor, size: 22),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null) ...[
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.getUserProfile(widget.user.uid),
      builder: (context, snapshot) {
        String? base64Picture;
        String displayName = widget.user.displayName ?? 'Myself';
        String currencyCode = 'MYR';

        if (snapshot.hasData && snapshot.data!.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          base64Picture = data['profilePicture'] as String?;
          if (data['displayName'] != null && (data['displayName'] as String).isNotEmpty) {
            displayName = data['displayName'] as String;
          }
          if (data['currencyCode'] != null) {
            currencyCode = data['currencyCode'] as String;
          }
        }

        if (displayName.trim().isEmpty) displayName = 'Myself';

        return Scaffold(
          backgroundColor: const Color(0xFF0F1626),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A2642),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildProfileAvatar(base64Picture),
                  if (base64Picture != null && base64Picture.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _isUploading ? null : _removeProfileImage,
                      child: const Text(
                        'Remove Photo',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _buildMenuItem(
                    icon: Icons.person_outline,
                    title: 'Personal Information',
                    onTap: () {
                      Navigator.push(
                        context,
                        _createSlideRightRoute(
                          PersonalInfoScreen(user: widget.user),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.format_list_bulleted,
                    title: 'Categories',
                    onTap: () {
                      Navigator.push(
                        context,
                        _createSlideRightRoute(
                          CategoriesScreen(user: widget.user),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.currency_exchange,
                    title: 'Currency',
                    subtitle: currencyCode,
                    onTap: () {
                      Navigator.push(
                        context,
                        _createSlideRightRoute(
                          CurrencyScreen(user: widget.user),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  _buildMenuItem(
                    icon: Icons.logout,
                    iconColor: Colors.redAccent,
                    textColor: Colors.redAccent,
                    title: 'Sign out',
                    onTap: _showSignOutConfirmation,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}