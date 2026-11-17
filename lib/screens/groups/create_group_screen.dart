import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'group_permissions_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  final User user;

  const CreateGroupScreen({super.key, required this.user});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();

  GroupPermissions _permissions = GroupPermissions();
  bool _isCreating = false;
  bool _isPickingImage = false;
  String? _base64Image;

  // Design Theme Palette
  static const Color purpleBackground = Color(0xFF2C2A78);
  static const Color inputFillColor = Color(0xFF35328B);
  static const Color inputBorderColor = Color(0xFF3F3B9E);
  static const Color cyanAccent = Color(0xFF3FE4F3);
  static const Color textMuted = Color(0xFFA5A8CD);

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 75,
      );

      if (pickedFile == null) return;

      setState(() => _isPickingImage = true);

      final bytes = await pickedFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      setState(() {
        _base64Image = base64Image;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _submitGroup() async {
    final String groupName = _nameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final double budget = double.tryParse(_budgetController.text.trim()) ?? 0.0;
      final String inviteCode = (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString();

      await _db.collection('groups').add({
        'name': groupName,
        'description': _descriptionController.text.trim(),
        'budget': double.parse(budget.toStringAsFixed(2)),
        'avatarBase64': _base64Image,
        'createdBy': widget.user.uid,
        'members': [widget.user.uid],
        'inviteCode': inviteCode,
        'permissions': _permissions.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Widget _buildGroupAvatar() {
    return GestureDetector(
      onTap: _isPickingImage ? null : _pickGroupImage,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF222060),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: ClipOval(
              child: _base64Image != null && _base64Image!.isNotEmpty
                  ? Image.memory(
                base64Decode(_base64Image!),
                width: 68,
                height: 68,
                fit: BoxFit.cover,
              )
                  : const Icon(
                Icons.group,
                size: 34,
                color: textMuted,
              ),
            ),
          ),
          if (_isPickingImage)
            const CircularProgressIndicator(color: cyanAccent),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Color(0xFF1D61E7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: purpleBackground,
      appBar: AppBar(
        backgroundColor: purpleBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New group',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar & Name
            Row(
              children: [
                _buildGroupAvatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildInputField(
                    controller: _nameController,
                    hintText: 'Enter group name',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Group Description
            Row(
              children: const [
                Text(
                  'Group description',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 6),
                Icon(Icons.info_outline, color: textMuted, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            _buildInputField(
              controller: _descriptionController,
              hintText: 'Enter group description',
            ),

            const SizedBox(height: 24),

            // Group Budget Field (Matches Add Expense format)
            Row(
              children: const [
                Text(
                  'Group budget',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 6),
                Icon(Icons.savings_outlined, color: textMuted, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            _buildInputField(
              controller: _budgetController,
              hintText: '00.00',
              prefixText: '\$ ',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
            ),

            const SizedBox(height: 28),

            // Group Permissions Row
            InkWell(
              onTap: () async {
                final updatedPermissions = await Navigator.push<GroupPermissions>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupPermissionsScreen(
                      initialPermissions: _permissions,
                    ),
                  ),
                );
                if (updatedPermissions != null) {
                  setState(() => _permissions = updatedPermissions);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Group permissions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(Icons.settings_outlined, color: textMuted, size: 22),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Members Section
            const Text(
              'Members: None',
              style: TextStyle(color: textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),

            // Add Member Button
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add member clicked')),
                );
              },
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: cyanAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_outlined, color: purpleBackground, size: 24),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add member',
                    style: TextStyle(color: textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: cyanAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: _isCreating ? null : _submitGroup,
        child: _isCreating
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: purpleBackground, strokeWidth: 2.5),
        )
            : const Icon(Icons.check, color: purpleBackground, size: 28),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: inputFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inputBorderColor, width: 1.2),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: textMuted, fontSize: 14),
          prefixText: prefixText,
          prefixStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
        ),
      ),
    );
  }
}