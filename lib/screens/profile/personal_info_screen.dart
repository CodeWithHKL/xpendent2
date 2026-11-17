import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

class PersonalInfoScreen extends StatefulWidget {
  final User user;

  const PersonalInfoScreen({super.key, required this.user});

  @override
  State<PersonalInfoScreen> createState() {
    return _PersonalInfoScreenState();
  }
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _picker = ImagePicker();

  late final Stream<DocumentSnapshot> _userProfileStream;

  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _universityController;
  late TextEditingController _yearController;

  final FocusNode _universityFocusNode = FocusNode();
  final FocusNode _yearFocusNode = FocusNode();

  bool _budgetAlerts = true;
  bool _goalReminders = true;
  bool _expenseNotifications = true;

  OverlayEntry? _popupOverlay;
  Timer? _popupTimer;

  DocumentReference<Map<String, dynamic>> _notificationSettingsDoc() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('settings')
        .doc('notifications');
  }

  static const List<String> _universitySuggestions = [
    'Universiti Tenaga Nasional (UNITEN)',
    'Universiti Malaya (UM)',
    'Universiti Putra Malaysia (UPM)',
    'Universiti Kebangsaan Malaysia (UKM)',
    'Universiti Sains Malaysia (USM)',
    'Universiti Teknologi Malaysia (UTM)',
    'Universiti Teknologi MARA (UiTM)',
    'International Islamic University Malaysia (IIUM / UIAM)',
    'Universiti Utara Malaysia (UUM)',
    'Universiti Malaysia Pahang Al-Sultan Abdullah (UMPSA)',
    'Universiti Tun Hussein Onn Malaysia (UTHM)',
    'Universiti Teknikal Malaysia Melaka (UTeM)',
    'Universiti Malaysia Perlis (UniMAP)',
    'Universiti Malaysia Terengganu (UMT)',
    'Universiti Malaysia Sabah (UMS)',
    'Universiti Malaysia Sarawak (UNIMAS)',
    'Universiti Pendidikan Sultan Idris (UPSI)',
    'Universiti Sains Islam Malaysia (USIM)',
    'Universiti Sultan Zainal Abidin (UniSZA)',
    'Universiti Malaysia Kelantan (UMK)',
    'Universiti Pertahanan Nasional Malaysia (UPNM)',
    'Universiti Teknologi PETRONAS (UTP)',
    'Multimedia University (MMU)',
    'Universiti Tunku Abdul Rahman (UTAR)',
    'Tunku Abdul Rahman University of Management and Technology (TAR UMT)',
    'Taylor\'s University',
    'Sunway University',
    'Monash University Malaysia',
    'University of Nottingham Malaysia',
    'Heriot-Watt University Malaysia',
    'Xiamen University Malaysia',
    'Asia Pacific University of Technology & Innovation (APU)',
    'UCSI University',
    'INTI International University',
    'Management and Science University (MSU)',
    'Universiti Kuala Lumpur (UniKL)',
    'SEGi University',
    'HELP University',
    'Infrastructure University Kuala Lumpur (IUKL)',
    'Limkokwing University of Creative Technology',
    'National University of Singapore (NUS)',
    'Nanyang Technological University (NTU)',
  ];

  static const List<String> _yearSuggestions = [
    'Foundation / Diploma',
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year+',
    'Postgraduate',
  ];

  @override
  void initState() {
    super.initState();
    _userProfileStream = _firestoreService.getUserProfile(widget.user.uid);
    _nameController = TextEditingController(text: widget.user.displayName ?? 'Myself');
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _universityController = TextEditingController();
    _yearController = TextEditingController();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    bool budget = await _notificationService.isBudgetAlertsEnabled();
    bool goal = await _notificationService.isGoalRemindersEnabled();
    bool expense = await _notificationService.isExpenseNotificationsEnabled();

    try {
      final settingsSnap = await _notificationSettingsDoc().get();
      if (settingsSnap.exists && settingsSnap.data() != null) {
        final data = settingsSnap.data()!;
        if (data['budgetAlerts'] is bool) {
          budget = data['budgetAlerts'] as bool;
          await _notificationService.setBudgetAlertsEnabled(budget);
        }
        if (data['goalReminders'] is bool) {
          goal = data['goalReminders'] as bool;
          await _notificationService.setGoalRemindersEnabled(goal);
        }
        if (data['expenseNotifications'] is bool) {
          expense = data['expenseNotifications'] as bool;
          await _notificationService.setExpenseNotificationsEnabled(expense);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _budgetAlerts = budget;
        _goalReminders = goal;
        _expenseNotifications = expense;
      });
    }
  }

  void _removePopup() {
    _popupTimer?.cancel();
    _popupTimer = null;
    _popupOverlay?.remove();
    _popupOverlay = null;
  }

  void _showStatusPopup({
    required String message,
    required bool isEnabled,
  }) {
    if (!mounted) return;
    _removePopup();

    final overlay = Overlay.of(context);

    _popupOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Center(
              child: _SmallPopupPill(
                message: message,
                isEnabled: isEnabled,
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_popupOverlay!);
    _popupTimer = Timer(const Duration(milliseconds: 1500), _removePopup);
  }

  Future<void> _toggleBudgetAlerts(bool value) async {
    setState(() {
      _budgetAlerts = value;
    });
    await _notificationService.setBudgetAlertsEnabled(value);

    await _notificationSettingsDoc().set(
      {'budgetAlerts': value},
      SetOptions(merge: true),
    );

    _showStatusPopup(
      message: value ? 'Budget alert enabled' : 'Budget alert disabled',
      isEnabled: value,
    );
  }

  Future<void> _toggleGoalReminders(bool value) async {
    setState(() {
      _goalReminders = value;
    });

    final goals = await _firestoreService.getGoals(widget.user.uid).first;
    await _notificationService.setGoalRemindersEnabled(value, activeGoals: goals);

    await _notificationSettingsDoc().set(
      {'goalReminders': value},
      SetOptions(merge: true),
    );

    _showStatusPopup(
      message: value ? 'Goal reminder enabled' : 'Goal reminder disabled',
      isEnabled: value,
    );
  }

  Future<void> _toggleExpenseNotifications(bool value) async {
    setState(() {
      _expenseNotifications = value;
    });
    await _notificationService.setExpenseNotificationsEnabled(value);

    await _notificationSettingsDoc().set(
      {'expenseNotifications': value},
      SetOptions(merge: true),
    );

    _showStatusPopup(
      message: value ? 'Expense alert enabled' : 'Expense alert disabled',
      isEnabled: value,
    );
  }

  @override
  void dispose() {
    _removePopup();
    _nameController.dispose();
    _emailController.dispose();
    _universityController.dispose();
    _yearController.dispose();
    _universityFocusNode.dispose();
    _yearFocusNode.dispose();
    super.dispose();
  }

  void _cancelEditing() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isEditing = false;
    });
  }

  Future<void> _pickAndChangeProfileImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 75,
    );

    if (pickedFile == null) return;

    try {
      final bytes = await pickedFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      await _firestoreService.updateUserProfilePicture(widget.user.uid, base64Image);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  Future<void> _saveProfileData() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });
    try {
      final String newName = _nameController.text.trim();
      final String newEmail = _emailController.text.trim();

      if (newName != widget.user.displayName) {
        await widget.user.updateDisplayName(newName);
      }

      await _firestoreService.updateUserPersonalInfo(
        widget.user.uid,
        displayName: newName,
        email: newEmail,
      );

      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
        'university': _universityController.text.trim(),
        'year': _yearController.text.trim(),
      }, SetOptions(merge: true));

      await widget.user.reload();

      setState(() {
        _isEditing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Information updated successfully!'),
            backgroundColor: Color(0xFF1D61E7),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save changes: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
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
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
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
        Navigator.of(context).popUntil((route) {
          return route.isFirst;
        });
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
          width: 90,
          height: 90,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }
    return Container(
      width: 90,
      height: 90,
      color: const Color(0xFF1E2D4A),
      child: const Icon(Icons.person, size: 50, color: Colors.white70),
    );
  }

  InputDecoration _buildEditInputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      prefixIcon: Icon(icon, color: Colors.white38, size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF121A2D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1D61E7), width: 1.5),
      ),
    );
  }

  Widget _buildReadOnlyRow({
    required String label,
    required String value,
    required String fallbackValue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : fallbackValue,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required TextEditingController controller,
    required String fallbackValue,
    required IconData icon,
    String hintText = '',
    TextInputType keyboardType = TextInputType.text,
  }) {
    if (!_isEditing) {
      return _buildReadOnlyRow(
        label: label,
        value: controller.text,
        fallbackValue: fallbackValue,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6C5CE7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _buildEditInputDecoration(
              hintText: hintText,
              icon: icon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutocompleteInfoField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required List<String> suggestions,
    required String hintText,
    required IconData icon,
    required IconData optionIcon,
    bool showAllWhenEmpty = false,
  }) {
    if (!_isEditing) {
      return _buildReadOnlyRow(
        label: label,
        value: controller.text,
        fallbackValue: '',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6C5CE7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              return RawAutocomplete<String>(
                textEditingController: controller,
                focusNode: focusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return showAllWhenEmpty
                        ? suggestions
                        : const Iterable<String>.empty();
                  }

                  final startsWithMatches = suggestions.where((item) {
                    return item.toLowerCase().startsWith(query);
                  }).toList();
                  final containsMatches = suggestions.where((item) {
                    return !item.toLowerCase().startsWith(query) &&
                        item.toLowerCase().contains(query);
                  }).toList();

                  final combined = [...startsWithMatches, ...containsMatches];
                  if (showAllWhenEmpty &&
                      combined.length == 1 &&
                      combined.first.toLowerCase() == query) {
                    return suggestions;
                  }
                  return combined;
                },
                onSelected: (String selection) {
                  controller.text = selection;
                  setState(() {});
                },
                fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
                  return TextField(
                    controller: textController,
                    focusNode: fieldFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (_) {
                      setState(() {});
                    },
                    onSubmitted: (_) {
                      onFieldSubmitted();
                    },
                    decoration: _buildEditInputDecoration(
                      hintText: hintText,
                      icon: icon,
                      suffixIcon: textController.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                        onPressed: () {
                          textController.clear();
                          fieldFocusNode.requestFocus();
                          setState(() {});
                        },
                      )
                          : (showAllWhenEmpty
                          ? const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 20)
                          : null),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Material(
                        color: const Color(0xFF121A2D),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: constraints.maxWidth,
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121A2D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF1D61E7).withOpacity(0.6),
                            ),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, __) {
                              return const Divider(
                                height: 1,
                                color: Colors.white10,
                              );
                            },
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return InkWell(
                                onTap: () {
                                  onSelected(option);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        optionIcon,
                                        size: 15,
                                        color: const Color(0xFF00C897),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationToggle(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF1D61E7),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userProfileStream,
      builder: (context, snapshot) {
        String? base64Picture;
        if (snapshot.hasData && snapshot.data?.data() != null) {
          final data = Map<String, dynamic>.from(snapshot.data!.data() as Map);
          base64Picture = data['profilePicture'] as String?;
          if (!_isEditing) {
            if (data['displayName'] != null) _nameController.text = data['displayName'];
            if (data['email'] != null) _emailController.text = data['email'];
            _universityController.text = (data['university'] as String?) ?? '';
            _yearController.text = (data['year'] as String?) ?? '';
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0D1527),
          body: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 50, bottom: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A1F4C), Color(0xFF0F3A4B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.white10,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                            const Text(
                              'Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickAndChangeProfileImage,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.purpleAccent, width: 2),
                              ),
                              child: ClipOval(
                                child: _buildAvatarImage(base64Picture),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1D61E7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _nameController.text.isNotEmpty ? _nameController.text : 'Myself',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _emailController.text,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18243E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isEditing ? const Color(0xFF1D61E7) : Colors.white10,
                            width: _isEditing ? 1.5 : 1.0,
                          ),
                          boxShadow: _isEditing
                              ? [
                            BoxShadow(
                              color: const Color(0xFF1D61E7).withOpacity(0.25),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ]
                              : [],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, color: Colors.white70, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Personal Information',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (_isEditing) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1D61E7).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'EDITING',
                                          style: TextStyle(
                                            color: Color(0xFF1D61E7),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (!_isEditing)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isEditing = true;
                                      });
                                    },
                                    child: const Icon(Icons.edit_outlined, color: Colors.teal, size: 18),
                                  )
                                else
                                  GestureDetector(
                                    onTap: _cancelEditing,
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(color: Colors.white54, fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 20),

                            _buildInfoField(
                              label: 'Full Name',
                              controller: _nameController,
                              fallbackValue: 'Myself',
                              hintText: 'Enter your name',
                              icon: Icons.person_outline,
                            ),
                            if (!_isEditing) const Divider(color: Colors.white12, height: 12),

                            _buildInfoField(
                              label: 'Email',
                              controller: _emailController,
                              fallbackValue: widget.user.email ?? '',
                              hintText: 'Enter your email',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            if (!_isEditing) const Divider(color: Colors.white12, height: 12),

                            _buildAutocompleteInfoField(
                              label: 'University',
                              controller: _universityController,
                              focusNode: _universityFocusNode,
                              suggestions: _universitySuggestions,
                              hintText: 'Type e.g. UNITEN, UM, UPM...',
                              icon: Icons.school_outlined,
                              optionIcon: Icons.account_balance_outlined,
                              showAllWhenEmpty: false,
                            ),
                            if (!_isEditing) const Divider(color: Colors.white12, height: 12),

                            _buildAutocompleteInfoField(
                              label: 'Year',
                              controller: _yearController,
                              focusNode: _yearFocusNode,
                              suggestions: _yearSuggestions,
                              hintText: 'Select or type year (e.g. 3rd Year)',
                              icon: Icons.calendar_today_outlined,
                              optionIcon: Icons.school_rounded,
                              showAllWhenEmpty: true,
                            ),

                            if (_isEditing) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1D61E7),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isSaving ? null : _saveProfileData,
                                  child: _isSaving
                                      ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                      : const Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18243E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.notifications_none, color: Colors.white70, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Notifications',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 20),
                            _buildNotificationToggle(
                              'Budget Alerts',
                              'Get notified when you approach or exceed your budget',
                              _budgetAlerts,
                              _toggleBudgetAlerts,
                            ),
                            const Divider(color: Colors.white12, height: 12),
                            _buildNotificationToggle(
                              'Goal Reminders',
                              'Reminders for your savings goals',
                              _goalReminders,
                              _toggleGoalReminders,
                            ),
                            const Divider(color: Colors.white12, height: 12),
                            _buildNotificationToggle(
                              'Expense Notifications',
                              'Alert for every new expense',
                              _expenseNotifications,
                              _toggleExpenseNotifications,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18243E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.shield_outlined, color: Colors.white70, size: 20),
                              title: const Text('Privacy & Security',
                                  style: TextStyle(color: Colors.white, fontSize: 13)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                              onTap: () {},
                            ),
                            const Divider(color: Colors.white12, height: 1),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.palette_outlined, color: Colors.white70, size: 20),
                              title: const Text('Appearance',
                                  style: TextStyle(color: Colors.white, fontSize: 13)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                              onTap: () {},
                            ),
                            const Divider(color: Colors.white12, height: 1),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                              title: const Text('Sign out',
                                  style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                              onTap: _showSignOutConfirmation,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SmallPopupPill extends StatefulWidget {
  final String message;
  final bool isEnabled;

  const _SmallPopupPill({
    required this.message,
    required this.isEnabled,
  });

  @override
  State<_SmallPopupPill> createState() {
    return _SmallPopupPillState();
  }
}

class _SmallPopupPillState extends State<_SmallPopupPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();

    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor =
    widget.isEnabled ? const Color(0xFF00C897) : Colors.amberAccent;

    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2945),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: accentColor.withOpacity(0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: accentColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}