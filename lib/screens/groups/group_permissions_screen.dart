import 'package:flutter/material.dart';

class GroupPermissions {
  bool editGroupSettings;
  bool sendNewMessages;
  bool addOtherMembers;
  bool approveNewMembers;

  GroupPermissions({
    this.editGroupSettings = true,
    this.sendNewMessages = true,
    this.addOtherMembers = true,
    this.approveNewMembers = true,
  });

  Map<String, dynamic> toMap() => {
    'editGroupSettings': editGroupSettings,
    'sendNewMessages': sendNewMessages,
    'addOtherMembers': addOtherMembers,
    'approveNewMembers': approveNewMembers,
  };
}

class GroupPermissionsScreen extends StatefulWidget {
  final GroupPermissions initialPermissions;

  const GroupPermissionsScreen({
    super.key,
    required this.initialPermissions,
  });

  @override
  State<GroupPermissionsScreen> createState() => _GroupPermissionsScreenState();
}

class _GroupPermissionsScreenState extends State<GroupPermissionsScreen> {
  late GroupPermissions _permissions;

  // Design Theme Palette
  static const Color purpleBackground = Color(0xFF2C2A78);
  static const Color cyanAccent = Color(0xFF3FE4F3);
  static const Color textMuted = Color(0xFFA5A8CD);

  @override
  void initState() {
    super.initState();
    _permissions = GroupPermissions(
      editGroupSettings: widget.initialPermissions.editGroupSettings,
      sendNewMessages: widget.initialPermissions.sendNewMessages,
      addOtherMembers: widget.initialPermissions.addOtherMembers,
      approveNewMembers: widget.initialPermissions.approveNewMembers,
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
          onPressed: () => Navigator.pop(context, _permissions),
        ),
        title: const Text(
          'Group permission',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Members can:',
              style: TextStyle(color: textMuted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildPermissionItem(
              icon: Icons.edit_outlined,
              title: 'Edit group settings',
              subtitle:
              'This includes the name, icon, description, add new budget, and the ability to pin message.',
              value: _permissions.editGroupSettings,
              onChanged: (val) {
                setState(() => _permissions.editGroupSettings = val);
              },
            ),
            _buildPermissionItem(
              icon: Icons.chat_bubble_outline,
              title: 'Send new messages',
              subtitle: null,
              value: _permissions.sendNewMessages,
              onChanged: (val) {
                setState(() => _permissions.sendNewMessages = val);
              },
            ),
            _buildPermissionItem(
              icon: Icons.person_add_outlined,
              title: 'Add other members',
              subtitle: null,
              value: _permissions.addOtherMembers,
              onChanged: (val) {
                setState(() => _permissions.addOtherMembers = val);
              },
            ),
            _buildPermissionItem(
              icon: Icons.how_to_reg_outlined,
              title: 'Approve new members',
              subtitle: null,
              value: _permissions.approveNewMembers,
              onChanged: (val) {
                setState(() => _permissions.approveNewMembers = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textMuted, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: cyanAccent,
            activeTrackColor: cyanAccent.withOpacity(0.4),
            inactiveThumbColor: Colors.grey.shade400,
            inactiveTrackColor: Colors.white12,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}