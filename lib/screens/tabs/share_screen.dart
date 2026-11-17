import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/notification_service.dart';
import '../groups/create_group_screen.dart';

// =========================================================================
// SHARED THEME PALETTE & SMOOTH SLIDE ROUTE
// =========================================================================

class _ShareTheme {
  static const Color background = Color(0xFF0F1626);
  static const Color header = Color(0xFF132247);
  static const Color card = Color(0xFF1A2642);
  static const Color cardElevated = Color(0xFF202E4F);
  static const Color accent = Color(0xFF6C5CE7);
  static const Color mint = Color(0xFF00C897);
  static const Color mintBright = Color(0xFF00E676);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Colors.white54;
}

class _SmoothSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  _SmoothSlidePageRoute({required this.page})
      : super(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final slideAnimation = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(curvedAnimation);

      final fadeAnimation = Tween<double>(
        begin: 0.85,
        end: 1.0,
      ).animate(curvedAnimation);

      return SlideTransition(
        position: slideAnimation,
        child: FadeTransition(
          opacity: fadeAnimation,
          child: child,
        ),
      );
    },
  );
}

// =========================================================================
// CURRENCY RESOLUTION HELPER
// =========================================================================

String _resolveCurrencySymbol(Map<String, dynamic>? userProfileData) {
  if (userProfileData == null) return 'RM';
  final String? symbol = userProfileData['currencySymbol'] as String?;
  final String? code = userProfileData['currencyCode'] as String?;
  if (symbol != null && symbol.isNotEmpty) {
    return symbol;
  }
  if (code != null && code.isNotEmpty) {
    switch (code.toUpperCase()) {
      case 'MYR':
        return 'RM';
      case 'SGD':
        return 'S\$';
      case 'JPY':
      case 'CNY':
        return '¥';
      case 'HKD':
        return 'HK\$';
      case 'KRW':
        return '₩';
      case 'THB':
        return '฿';
      case 'IDR':
        return 'Rp';
      case 'VND':
        return '₫';
      case 'PHP':
        return '₱';
      case 'TWD':
        return 'NT\$';
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AUD':
        return 'A\$';
      case 'CAD':
        return 'C\$';
      case 'NZD':
        return 'NZ\$';
      default:
        return code;
    }
  }
  return 'RM';
}

// =========================================================================
// NUMERIC-ONLY CURRENCY FORMATTER (00.00 FORMAT, BLOCKS ALPHABETS)
// =========================================================================

class _Currency00Dot00Formatter extends TextInputFormatter {
  static String formatFromCents(int cents) {
    final int safeCents = cents < 0 ? 0 : cents;
    final int whole = safeCents ~/ 100;
    final int fraction = safeCents % 100;
    return '${whole.toString().padLeft(2, '0')}.${fraction.toString().padLeft(2, '0')}';
  }

  static String formatFromDouble(double value) {
    final int cents = (value * 100).round();
    return formatFromCents(cents);
  }

  static double parseToDouble(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0.0;
    final int cents = int.tryParse(digits) ?? 0;
    return cents / 100.0;
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '00.00',
        selection: TextSelection.collapsed(offset: 5),
      );
    }

    final String boundedDigits = digitsOnly.length > 8
        ? digitsOnly.substring(digitsOnly.length - 8)
        : digitsOnly;

    final int cents = int.tryParse(boundedDigits) ?? 0;
    final String formatted = formatFromCents(cents);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// =========================================================================
// EXPENSE CATEGORY HELPERS
// =========================================================================

class _ExpenseCategoryMeta {
  final String name;
  final IconData icon;
  final Color color;

  const _ExpenseCategoryMeta(this.name, this.icon, this.color);
}

const List<_ExpenseCategoryMeta> _kGroupExpenseCategories = [
  _ExpenseCategoryMeta(
      'Food & Dining', Icons.restaurant_rounded, Color(0xFFFF7675)),
  _ExpenseCategoryMeta(
      'Groceries', Icons.shopping_cart_outlined, Color(0xFF00C897)),
  _ExpenseCategoryMeta(
      'Transport', Icons.directions_car_outlined, Color(0xFF74B9FF)),
  _ExpenseCategoryMeta(
      'Accommodation', Icons.hotel_outlined, Color(0xFFA29BFE)),
  _ExpenseCategoryMeta(
      'Bills & Utilities', Icons.receipt_long_outlined, Color(0xFFFDCB6E)),
  _ExpenseCategoryMeta(
      'Entertainment', Icons.movie_outlined, Color(0xFFFD79A8)),
  _ExpenseCategoryMeta(
      'General', Icons.shopping_bag_outlined, Color(0xFF6C5CE7)),
];

_ExpenseCategoryMeta _getCategoryMeta(String? categoryName) {
  if (categoryName == null || categoryName.trim().isEmpty) {
    return _kGroupExpenseCategories.last;
  }
  return _kGroupExpenseCategories.firstWhere(
        (c) => c.name.toLowerCase() == categoryName.trim().toLowerCase(),
    orElse: () => _kGroupExpenseCategories.last,
  );
}

// =========================================================================
// PHONE NOTIFICATION DISPATCHER FOR GROUP MESSAGES & SHARED EXPENSES
// =========================================================================

class _GroupPhoneNotifier {
  _GroupPhoneNotifier._();
  static final _GroupPhoneNotifier instance = _GroupPhoneNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  final NotificationService _notificationService = NotificationService();

  bool _initialized = false;
  bool _hasSeededInitialState = false;
  final Map<String, int> _lastNotifiedMsgMillis = {};

  String? activeOpenGroupId;

  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;

    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> processGroupSnapshots(
      List<QueryDocumentSnapshot> docs,
      String currentUid,
      ) async {
    if (kIsWeb) return;
    await ensureInitialized();

    if (!_hasSeededInitialState) {
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final Timestamp? ts = data['lastMessageTime'] as Timestamp?;
        if (ts != null) {
          _lastNotifiedMsgMillis[doc.id] = ts.millisecondsSinceEpoch;
        }
      }
      _hasSeededInitialState = true;
      return;
    }

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String groupId = doc.id;
      final Timestamp? ts = data['lastMessageTime'] as Timestamp?;
      if (ts == null) continue;

      final int msgMillis = ts.millisecondsSinceEpoch;
      final int? previousMillis = _lastNotifiedMsgMillis[groupId];

      if (previousMillis != null && msgMillis <= previousMillis) {
        continue;
      }
      _lastNotifiedMsgMillis[groupId] = msgMillis;

      final String? senderId = data['lastMessageSenderId'] as String?;
      if (senderId == null || senderId == currentUid) continue;
      if (activeOpenGroupId == groupId) continue;

      final String groupName = (data['name'] as String?) ?? 'Group Expense';
      final String senderName =
          (data['lastMessageSender'] as String?) ?? 'Member';
      final String rawMessage = (data['lastMessage'] as String?) ?? '';
      if (rawMessage.trim().isEmpty) continue;

      final bool isExpenseAlert = rawMessage.startsWith('💵') ||
          rawMessage.contains('added shared expense:');

      if (isExpenseAlert) {
        final expenseEnabled =
        await _notificationService.isExpenseNotificationsEnabled();
        if (!expenseEnabled) continue;
      }

      final String title =
      isExpenseAlert ? 'New Group Expense • $groupName' : groupName;
      final String body =
      isExpenseAlert ? rawMessage : '$senderName: $rawMessage';

      await _showPhoneNotification(
        id: groupId.hashCode ^ msgMillis.hashCode,
        title: title,
        body: body,
        isExpense: isExpenseAlert,
      );
    }
  }

  Future<void> _showPhoneNotification({
    required int id,
    required String title,
    required String body,
    required bool isExpense,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      isExpense ? 'group_expenses_channel' : 'group_messages_channel',
      isExpense ? 'Group Expenses' : 'Group Messages',
      channelDescription: isExpense
          ? 'Notifications when a group member adds a shared expense'
          : 'Notifications for new group chat messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}

// =========================================================================
// REUSABLE BOTTOM NAV ICON WITH NEW MESSAGE INDICATOR
// =========================================================================

class ShareNavBadgeIcon extends StatefulWidget {
  final User user;
  final bool isSelected;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;

  const ShareNavBadgeIcon({
    super.key,
    required this.user,
    required this.isSelected,
    this.activeIcon = Icons.share,
    this.inactiveIcon = Icons.share_outlined,
    this.activeColor = _ShareTheme.accent,
    this.inactiveColor = Colors.grey,
  });

  static bool hasUnreadInGroup(
      Map<String, dynamic> groupData, String currentUid) {
    final String? lastSenderId = groupData['lastMessageSenderId'] as String?;
    final Timestamp? lastMsgTime = groupData['lastMessageTime'] as Timestamp?;
    if (lastMsgTime == null) return false;
    if (lastSenderId == currentUid) return false;

    final Map<String, dynamic>? lastReadMap = groupData['lastReadAt'] is Map
        ? Map<String, dynamic>.from(groupData['lastReadAt'])
        : null;
    final Timestamp? myLastRead = lastReadMap?[currentUid] as Timestamp?;

    if (myLastRead == null) return true;
    return lastMsgTime.toDate().isAfter(myLastRead.toDate());
  }

  @override
  State<ShareNavBadgeIcon> createState() => _ShareNavBadgeIconState();
}

class _ShareNavBadgeIconState extends State<ShareNavBadgeIcon> {
  late final Stream<QuerySnapshot> _groupsStream;

  @override
  void initState() {
    super.initState();
    _GroupPhoneNotifier.instance.ensureInitialized();
    _groupsStream = FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: widget.user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        int unreadGroupsCount = 0;
        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;

          _GroupPhoneNotifier.instance
              .processGroupSnapshots(docs, widget.user.uid);

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (ShareNavBadgeIcon.hasUnreadInGroup(data, widget.user.uid)) {
              unreadGroupsCount++;
            }
          }
        }

        final bool hasUnread = unreadGroupsCount > 0;
        final IconData displayIcon = (widget.isSelected || hasUnread)
            ? widget.activeIcon
            : widget.inactiveIcon;
        final Color displayColor = widget.isSelected
            ? widget.activeColor
            : (hasUnread ? _ShareTheme.mintBright : widget.inactiveColor);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(displayIcon, color: displayColor, size: 24),
            if (hasUnread)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4.5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _ShareTheme.mint,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _ShareTheme.header, width: 1.5),
                  ),
                  constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadGroupsCount > 9 ? '9+' : '$unreadGroupsCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _ShareTheme.background,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// =========================================================================
// MAIN SHARE SCREEN (GROUP LIST)
// =========================================================================

class ShareScreen extends StatefulWidget {
  final User user;

  const ShareScreen({super.key, required this.user});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _navigateToCreateGroup() {
    Navigator.push(
      context,
      _SmoothSlidePageRoute(
        page: CreateGroupScreen(user: widget.user),
      ),
    );
  }

  void _showJoinGroupDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ShareTheme.header,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Join via Invite Code',
          style: TextStyle(
              color: _ShareTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            color: _ShareTheme.textPrimary,
            fontSize: 18,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            labelText: '6-Digit Code',
            hintText: '000000',
            hintStyle: const TextStyle(color: Colors.white24),
            labelStyle:
            const TextStyle(color: _ShareTheme.textMuted, letterSpacing: 0),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: _ShareTheme.accent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel',
                style: TextStyle(color: _ShareTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ShareTheme.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.length != 6) return;

              final query = await _db
                  .collection('groups')
                  .where('inviteCode', isEqualTo: code)
                  .get();

              if (query.docs.isNotEmpty) {
                final docRef = query.docs.first.reference;
                final List members = query.docs.first.data()['members'] ?? [];

                if (!members.contains(widget.user.uid)) {
                  members.add(widget.user.uid);
                  await docRef.update({'members': members});
                }
                if (mounted) Navigator.pop(dialogContext);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid invite code!')),
                  );
                }
              }
            },
            child: const Text('Join Group',
                style: TextStyle(
                    color: _ShareTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupAvatarImage(String? avatarBase64, String groupName,
      {double radius = 24, double fontSize = 18}) {
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      try {
        final cleanBase64 = avatarBase64.contains(',')
            ? avatarBase64.split(',').last.trim()
            : avatarBase64.trim();
        final bytes = base64Decode(cleanBase64);
        return CircleAvatar(
          radius: radius,
          backgroundColor: _ShareTheme.accent.withOpacity(0.2),
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: _ShareTheme.accent.withOpacity(0.2),
      child: Text(
        groupName.isNotEmpty ? groupName[0].toUpperCase() : 'G',
        style: TextStyle(
            color: _ShareTheme.accent,
            fontWeight: FontWeight.bold,
            fontSize: fontSize),
      ),
    );
  }

  String _formatChatPreviewTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final DateTime date = timestamp.toDate();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) {
      return DateFormat('h:mm a').format(date);
    } else if (today.difference(messageDay).inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('dd/MM/yy').format(date);
    }
  }

  Widget _buildGroupListCard({
    required String groupId,
    required Map<String, dynamic> groupData,
  }) {
    final String groupName = groupData['name'] ?? 'Group';
    final String inviteCode = groupData['inviteCode'] ?? '';
    final String? avatarBase64 = groupData['avatarBase64'];
    final String? storedLastMessage = groupData['lastMessage'] as String?;
    final String? storedLastSender = groupData['lastMessageSender'] as String?;
    final String? storedLastSenderId =
    groupData['lastMessageSenderId'] as String?;
    final Timestamp? storedLastTime =
    groupData['lastMessageTime'] as Timestamp?;
    final bool isUnread =
    ShareNavBadgeIcon.hasUnreadInGroup(groupData, widget.user.uid);

    if (storedLastMessage != null && storedLastMessage.isNotEmpty) {
      return _buildGroupCardTile(
        groupId: groupId,
        groupName: groupName,
        inviteCode: inviteCode,
        avatarBase64: avatarBase64,
        lastMessageText: storedLastMessage,
        lastSenderName: storedLastSender,
        lastSenderId: storedLastSenderId,
        lastMessageTime: storedLastTime,
        isUnread: isUnread,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, msgSnapshot) {
        String? latestText;
        String? latestSender;
        String? latestSenderId;
        Timestamp? latestTime;

        if (msgSnapshot.hasData && msgSnapshot.data!.docs.isNotEmpty) {
          final latestMsg =
          msgSnapshot.data!.docs.first.data() as Map<String, dynamic>;
          latestText = latestMsg['text'] as String?;
          latestSender =
          (latestMsg['senderName'] ?? latestMsg['senderEmail']) as String?;
          latestSenderId = latestMsg['senderId'] as String?;
          latestTime = latestMsg['timestamp'] as Timestamp?;
        }

        return _buildGroupCardTile(
          groupId: groupId,
          groupName: groupName,
          inviteCode: inviteCode,
          avatarBase64: avatarBase64,
          lastMessageText: latestText,
          lastSenderName: latestSender,
          lastSenderId: latestSenderId,
          lastMessageTime: latestTime,
          isUnread: isUnread,
        );
      },
    );
  }

  Widget _buildGroupCardTile({
    required String groupId,
    required String groupName,
    required String inviteCode,
    required String? avatarBase64,
    required String? lastMessageText,
    required String? lastSenderName,
    required String? lastSenderId,
    required Timestamp? lastMessageTime,
    required bool isUnread,
  }) {
    final bool hasMessage =
        lastMessageText != null && lastMessageText.trim().isNotEmpty;
    final String formattedTime = _formatChatPreviewTime(lastMessageTime);

    String previewLine;
    if (hasMessage) {
      if (lastSenderId == widget.user.uid) {
        previewLine = 'You: $lastMessageText';
      } else if (lastSenderName != null && lastSenderName.trim().isNotEmpty) {
        previewLine = '$lastSenderName: $lastMessageText';
      } else {
        previewLine = lastMessageText;
      }
    } else {
      previewLine = 'Invite Code: $inviteCode';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _ShareTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread
              ? _ShareTheme.mint.withOpacity(0.55)
              : Colors.white10,
          width: isUnread ? 1.3 : 1.0,
        ),
      ),
      child: ListTile(
        tileColor: Colors.transparent,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildGroupAvatarImage(avatarBase64, groupName,
            radius: 24, fontSize: 18),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ShareTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formattedTime.isNotEmpty ? formattedTime : 'Active',
              style: TextStyle(
                color: isUnread
                    ? _ShareTheme.mintBright
                    : (formattedTime.isNotEmpty
                    ? _ShareTheme.textMuted
                    : Colors.greenAccent),
                fontSize: 11.5,
                fontWeight: isUnread || formattedTime.isEmpty
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5.0),
          child: Row(
            children: [
              if (hasMessage && lastSenderId == widget.user.uid)
                const Padding(
                  padding: EdgeInsets.only(right: 4.0),
                  child:
                  Icon(Icons.done_all, size: 15, color: Colors.cyanAccent),
                ),
              Expanded(
                child: Text(
                  previewLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isUnread ? Colors.white : _ShareTheme.textMuted,
                    fontSize: 13,
                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _ShareTheme.mint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: _ShareTheme.background,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: _ShareTheme.textMuted, size: 15),
        onTap: () {
          Navigator.push(
            context,
            _SmoothSlidePageRoute(
              page: WhatsAppGroupDetailScreen(
                user: widget.user,
                groupId: groupId,
                groupName: groupName,
                avatarBase64: avatarBase64,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ShareTheme.background,
      appBar: AppBar(
        backgroundColor: _ShareTheme.header,
        elevation: 0,
        title: const Text(
          'Shared Expenses',
          style: TextStyle(
              color: _ShareTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner,
                color: _ShareTheme.textMuted),
            onPressed: _showJoinGroupDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: _ShareTheme.header,
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ShareTheme.accent,
                      foregroundColor: _ShareTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _navigateToCreateGroup,
                    icon: const Icon(Icons.group_add, size: 20),
                    label: const Text('New Group',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: _ShareTheme.accent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _showJoinGroupDialog,
                    icon: const Icon(Icons.vpn_key_outlined,
                        color: _ShareTheme.accent, size: 20),
                    label: const Text('Join Code',
                        style: TextStyle(
                            color: _ShareTheme.textPrimary,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('groups')
                  .where('members', arrayContains: widget.user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error loading groups: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: _ShareTheme.accent));
                }

                final groups = [...(snapshot.data?.docs ?? [])];

                groups.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['lastMessageTime'] as Timestamp?;
                  final bTime = bData['lastMessageTime'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

                if (groups.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _ShareTheme.accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.groups_outlined,
                              size: 72,
                              color: _ShareTheme.accent,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No Active Groups Yet',
                            style: TextStyle(
                              color: _ShareTheme.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Create a group for roommates, trips, or events, or join an existing group with an invite code.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ShareTheme.textMuted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _ShareTheme.accent,
                                foregroundColor: _ShareTheme.textPrimary,
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _navigateToCreateGroup,
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 22),
                              label: const Text(
                                'Create Group Now',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: _ShareTheme.accent, width: 1.5),
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _showJoinGroupDialog,
                              icon: const Icon(Icons.vpn_key_outlined,
                                  color: _ShareTheme.accent, size: 20),
                              label: const Text(
                                'Join Existing Group',
                                style: TextStyle(
                                  color: _ShareTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final groupData =
                    groups[index].data() as Map<String, dynamic>;
                    final groupId = groups[index].id;

                    return _buildGroupListCard(
                      groupId: groupId,
                      groupData: groupData,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// HELPER MODEL, USER RESOLVER & UNIFIED EXPENSE CARD
// =========================================================================

class _MemberProfile {
  final String? uid;
  final String displayName;
  final String? email;
  final String? bio;
  final String? phone;
  final Uint8List? photoBytes;

  const _MemberProfile({
    this.uid,
    required this.displayName,
    this.email,
    this.bio,
    this.phone,
    this.photoBytes,
  });
}

Uint8List? _decodeProfilePhotoSafe(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final clean = raw.contains(',') ? raw.split(',').last.trim() : raw.trim();
    return base64Decode(clean);
  } catch (_) {
    return null;
  }
}

class _ResolvedMemberNameText extends StatelessWidget {
  final String? uid;
  final String? fallbackName;
  final String prefix;
  final TextStyle style;

  const _ResolvedMemberNameText({
    this.uid,
    this.fallbackName,
    this.prefix = '',
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final String fallback = (fallbackName != null &&
        fallbackName!.trim().isNotEmpty &&
        !fallbackName!.contains('@'))
        ? fallbackName!.trim()
        : (fallbackName != null && fallbackName!.contains('@')
        ? fallbackName!.split('@').first
        : 'Member');

    if (uid == null || uid!.trim().isEmpty) {
      return Text(
        '$prefix$fallback',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        String resolved = fallback;
        if (snap.hasData && snap.data!.exists && snap.data!.data() != null) {
          final data = snap.data!.data() as Map<String, dynamic>;
          final dbName = data['displayName'] as String?;
          if (dbName != null && dbName.trim().isNotEmpty) {
            resolved = dbName.trim();
          }
        }
        return Text(
          '$prefix$resolved',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

class _CleanExpenseCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String currencySymbol;
  final String formattedDate;
  final bool showPaidBy;
  final Color amountColor;
  final VoidCallback onTap;

  const _CleanExpenseCard({
    required this.data,
    required this.currencySymbol,
    required this.formattedDate,
    required this.onTap,
    this.showPaidBy = true,
    this.amountColor = _ShareTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final String title = (data['title'] as String?) ?? 'Expense';
    final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final String categoryName = (data['category'] as String?) ?? 'General';
    final bool isPaid = data['isPaid'] ?? false;
    final catMeta = _getCategoryMeta(categoryName);
    final String? paidById = data['paidById'] as String?;
    final String? paidByRaw = data['paidBy'] as String?;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _ShareTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPaid
                  ? _ShareTheme.mint.withOpacity(0.38)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: catMeta.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(catMeta.icon, color: catMeta.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ShareTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (isPaid) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _ShareTheme.mint.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Paid',
                              style: TextStyle(
                                color: _ShareTheme.mintBright,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (showPaidBy) ...[
                          Flexible(
                            child: _ResolvedMemberNameText(
                              uid: paidById,
                              fallbackName: paidByRaw,
                              prefix: 'Paid by ',
                              style: const TextStyle(
                                color: _ShareTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Text(
                            ' • ',
                            style:
                            TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$currencySymbol${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    catMeta.name,
                    style: TextStyle(
                      color: catMeta.color.withOpacity(0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>> _loadFullMemberStats({
  required FirebaseFirestore db,
  required String groupId,
  required String? targetUid,
  required String? fallbackName,
  required _MemberProfile? prefetchedProfile,
}) async {
  _MemberProfile profile = prefetchedProfile ??
      _MemberProfile(
        uid: targetUid,
        displayName: (fallbackName != null && fallbackName.trim().isNotEmpty)
            ? fallbackName.trim()
            : 'Member',
      );

  if (targetUid != null && targetUid.isNotEmpty) {
    try {
      final userDoc = await db.collection('users').doc(targetUid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final u = userDoc.data()!;
        final String? dbName = u['displayName'] as String?;
        final String? dbEmail = u['email'] as String?;
        final String? dbBio =
        (u['bio'] ?? u['about'] ?? u['status']) as String?;
        final String? dbPhone = (u['phone'] ?? u['phoneNumber']) as String?;
        final String? dbPhoto = u['profilePicture'] as String?;

        profile = _MemberProfile(
          uid: targetUid,
          displayName: (dbName != null && dbName.trim().isNotEmpty)
              ? dbName.trim()
              : profile.displayName,
          email: dbEmail ?? profile.email,
          bio: dbBio,
          phone: dbPhone,
          photoBytes: _decodeProfilePhotoSafe(dbPhoto) ?? profile.photoBytes,
        );
      }
    } catch (_) {}
  }

  double totalGroupSpent = 0.0;
  double memberPaid = 0.0;
  double memberOwedShare = 0.0;
  int memberExpenseCount = 0;
  int memberCount = 1;

  try {
    final groupDoc = await db.collection('groups').doc(groupId).get();
    final members = (groupDoc.data()?['members'] as List?) ?? [];
    if (members.isNotEmpty) memberCount = members.length;

    final expSnap = await db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .get();

    for (final doc in expSnap.docs) {
      final d = doc.data();
      final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
      totalGroupSpent += amt;

      if (targetUid != null && d['paidById'] == targetUid) {
        memberPaid += amt;
        memberExpenseCount++;
      }

      final Map<String, dynamic>? customSplits = d['customSplits'] is Map
          ? Map<String, dynamic>.from(d['customSplits'])
          : null;

      if (targetUid != null &&
          customSplits != null &&
          customSplits.containsKey(targetUid)) {
        memberOwedShare +=
            (customSplits[targetUid] as num?)?.toDouble() ?? 0.0;
      } else {
        memberOwedShare += members.isNotEmpty ? (amt / members.length) : amt;
      }
    }
  } catch (_) {}

  final double fairShare = totalGroupSpent / memberCount;
  final double netBalance = memberPaid - memberOwedShare;

  return {
    'profile': profile,
    'memberPaid': memberPaid,
    'memberExpenseCount': memberExpenseCount,
    'fairShare': fairShare,
    'netBalance': netBalance,
  };
}

Future<void> _showGroupMemberProfileSheet({
  required BuildContext context,
  required FirebaseFirestore db,
  required String groupId,
  required String currentUid,
  required String? targetUid,
  required String? fallbackName,
  required _MemberProfile? prefetchedProfile,
  required String currencySymbol,
  required List<String> members,
  required bool isCurrentUserAdmin,
  bool isAdmin = false,
  Widget? adminActionSection,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _ShareTheme.header,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _loadFullMemberStats(
          db: db,
          groupId: groupId,
          targetUid: targetUid,
          fallbackName: fallbackName,
          prefetchedProfile: prefetchedProfile,
        ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 220,
              child: Center(
                child: CircularProgressIndicator(color: _ShareTheme.accent),
              ),
            );
          }

          final data = snap.data!;
          final _MemberProfile profile = data['profile'] as _MemberProfile;
          final double memberPaid = data['memberPaid'] as double;
          final int expenseCount = data['memberExpenseCount'] as int;
          final double fairShare = data['fairShare'] as double;
          final double netBalance = data['netBalance'] as double;
          final bool isMe = targetUid != null && targetUid == currentUid;
          final String initial = profile.displayName.isNotEmpty
              ? profile.displayName[0].toUpperCase()
              : 'M';

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _ShareTheme.accent.withOpacity(0.8),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: profile.photoBytes != null
                        ? Image.memory(
                      profile.photoBytes!,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    )
                        : Container(
                      color: _ShareTheme.accent.withOpacity(0.22),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        isMe
                            ? '${profile.displayName} (You)'
                            : profile.displayName,
                        style: const TextStyle(
                          color: _ShareTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _ShareTheme.mint.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _ShareTheme.mint,
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'Group Admin',
                          style: TextStyle(
                            color: _ShareTheme.mint,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (profile.email != null &&
                    profile.email!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.email!,
                    style: const TextStyle(
                        color: _ShareTheme.textMuted, fontSize: 13),
                  ),
                ],
                if (profile.phone != null &&
                    profile.phone!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    profile.phone!,
                    style: const TextStyle(
                        color: _ShareTheme.textMuted, fontSize: 12.5),
                  ),
                ],
                if (profile.bio != null &&
                    profile.bio!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      profile.bio!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _ShareTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MEMBER SUMMARY',
                        style: TextStyle(
                          color: _ShareTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Paid',
                                    style: TextStyle(
                                        color: _ShareTheme.textMuted,
                                        fontSize: 11.5)),
                                const SizedBox(height: 3),
                                Text(
                                  '$currencySymbol${memberPaid.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$expenseCount ${expenseCount == 1 ? 'expense' : 'expenses'}',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Equal Share',
                                    style: TextStyle(
                                        color: _ShareTheme.textMuted,
                                        fontSize: 11.5)),
                                const SizedBox(height: 3),
                                Text(
                                  '$currencySymbol${fairShare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: _ShareTheme.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'Per member',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(netBalance >= 0 ? 'Gets Back' : 'Owes',
                                    style: const TextStyle(
                                        color: _ShareTheme.textMuted,
                                        fontSize: 11.5)),
                                const SizedBox(height: 3),
                                Text(
                                  '$currencySymbol${netBalance.abs().toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: netBalance >= 0
                                        ? _ShareTheme.mintBright
                                        : Colors.orangeAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  netBalance >= 0 ? 'Credit' : 'To settle',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ShareTheme.accent,
                      foregroundColor: _ShareTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      final rootNavigator = Navigator.of(context);
                      Navigator.pop(sheetContext);
                      rootNavigator.push(
                        _SmoothSlidePageRoute(
                          page: MemberPaidExpensesScreen(
                            currentUser: UserWrapper(currentUid),
                            targetUid: targetUid ?? '',
                            targetMemberName: profile.displayName,
                            groupId: groupId,
                            groupName: '',
                            members: members,
                            isCurrentUserAdmin: isCurrentUserAdmin,
                            currencySymbol: currencySymbol,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: Text(
                      isMe
                          ? 'View My Paid History'
                          : 'View ${profile.displayName}\'s Paid History',
                      style: const TextStyle(
                        color: _ShareTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (adminActionSection != null) ...[
                  const SizedBox(height: 14),
                  adminActionSection,
                ],
              ],
            ),
          );
        },
        ),
      ),
    ),
  );
}

class UserWrapper {
  final String uid;
  UserWrapper(this.uid);
}

// =========================================================================
// DEDICATED ALL EXPENSES SCREEN
// =========================================================================

class AllGroupExpensesScreen extends StatelessWidget {
  final User user;
  final String groupId;
  final String groupName;
  final List<String> members;
  final bool isCurrentUserAdmin;
  final String currencySymbol;

  const AllGroupExpensesScreen({
    super.key,
    required this.user,
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.isCurrentUserAdmin,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: _ShareTheme.background,
      appBar: AppBar(
        backgroundColor: _ShareTheme.header,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Group Expenses',
              style: TextStyle(
                color: _ShareTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (groupName.trim().isNotEmpty)
              Text(
                groupName,
                style: const TextStyle(
                  color: _ShareTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('groups')
            .doc(groupId)
            .collection('expenses')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _ShareTheme.accent),
            );
          }

          final expenses = snapshot.data!.docs;

          if (expenses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _ShareTheme.accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        size: 52,
                        color: _ShareTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Expenses Recorded',
                      style: TextStyle(
                        color: _ShareTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Expenses added to this group will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _ShareTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          double totalGroupAmount = 0.0;
          for (final doc in expenses) {
            final d = doc.data() as Map<String, dynamic>;
            totalGroupAmount += (d['amount'] as num?)?.toDouble() ?? 0.0;
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _ShareTheme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL GROUP SPENDING',
                          style: TextStyle(
                            color: _ShareTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$currencySymbol${totalGroupAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _ShareTheme.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${expenses.length} ${expenses.length == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expDoc = expenses[index];
                    final data = expDoc.data() as Map<String, dynamic>;
                    final Timestamp? ts = data['timestamp'] as Timestamp?;
                    final String formattedDate = ts != null
                        ? DateFormat('MMM dd, yyyy • hh:mm a').format(ts.toDate())
                        : 'Today';

                    return _CleanExpenseCard(
                      data: data,
                      currencySymbol: currencySymbol,
                      formattedDate: formattedDate,
                      showPaidBy: true,
                      amountColor: _ShareTheme.textPrimary,
                      onTap: () {
                        WhatsAppGroupDetailScreen.showExpenseDetailSheetStatic(
                          context: context,
                          db: db,
                          groupId: groupId,
                          currentUid: user.uid,
                          expenseId: expDoc.id,
                          expenseData: data,
                          members: members,
                          isCurrentUserAdmin: isCurrentUserAdmin,
                          currencySymbol: currencySymbol,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =========================================================================
// DEDICATED MEMBER PAID HISTORY SCREEN (FOR ANY USER)
// =========================================================================

class MemberPaidExpensesScreen extends StatelessWidget {
  final dynamic currentUser; // Can be User or UserWrapper
  final String targetUid;
  final String targetMemberName;
  final String groupId;
  final String groupName;
  final List<String> members;
  final bool isCurrentUserAdmin;
  final String currencySymbol;

  const MemberPaidExpensesScreen({
    super.key,
    required this.currentUser,
    required this.targetUid,
    required this.targetMemberName,
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.isCurrentUserAdmin,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final String currentUserId = currentUser is User
        ? (currentUser as User).uid
        : (currentUser as UserWrapper).uid;
    final bool isMe = targetUid == currentUserId;

    return Scaffold(
      backgroundColor: _ShareTheme.background,
      appBar: AppBar(
        backgroundColor: _ShareTheme.header,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isMe ? 'My Paid History' : '$targetMemberName\'s Paid History',
          style: const TextStyle(
            color: _ShareTheme.textPrimary,
            fontSize: 17.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('groups')
            .doc(groupId)
            .collection('expenses')
            .where('paidById', isEqualTo: targetUid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _ShareTheme.accent),
            );
          }

          final expenses = [...snapshot.data!.docs];
          expenses.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['timestamp']
            as Timestamp?;
            final bTs = (b.data() as Map<String, dynamic>)['timestamp']
            as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

          double totalUserPaid = 0.0;
          int settledCount = 0;
          for (final doc in expenses) {
            final data = doc.data() as Map<String, dynamic>;
            totalUserPaid += (data['amount'] as num?)?.toDouble() ?? 0.0;
            if (data['isPaid'] == true) settledCount++;
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                decoration: BoxDecoration(
                  color: _ShareTheme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe
                                ? 'TOTAL YOU HAVE PAID'
                                : 'TOTAL PAID BY ${targetMemberName.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ShareTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$currencySymbol${totalUserPaid.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${expenses.length} ${expenses.length == 1 ? 'expense' : 'expenses'} • $settledCount settled',
                            style: const TextStyle(
                                color: _ShareTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.cyanAccent,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: expenses.isEmpty
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _ShareTheme.accent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.payment_outlined,
                            size: 52,
                            color: _ShareTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isMe
                              ? 'No Expenses Paid By You Yet'
                              : 'No Expenses Paid By $targetMemberName Yet',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ShareTheme.textPrimary,
                            fontSize: 17.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When expenses are recorded, they will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _ShareTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expDoc = expenses[index];
                    final data = expDoc.data() as Map<String, dynamic>;
                    final Timestamp? ts =
                    data['timestamp'] as Timestamp?;
                    final String formattedDate = ts != null
                        ? DateFormat('MMM dd, yyyy • hh:mm a')
                        .format(ts.toDate())
                        : 'Today';

                    return _CleanExpenseCard(
                      data: data,
                      currencySymbol: currencySymbol,
                      formattedDate: formattedDate,
                      showPaidBy: false,
                      amountColor: Colors.cyanAccent,
                      onTap: () {
                        WhatsAppGroupDetailScreen
                            .showExpenseDetailSheetStatic(
                          context: context,
                          db: db,
                          groupId: groupId,
                          currentUid: currentUserId,
                          expenseId: expDoc.id,
                          expenseData: data,
                          members: members,
                          isCurrentUserAdmin: isCurrentUserAdmin,
                          currencySymbol: currencySymbol,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =========================================================================
// GROUP DETAIL SCREEN
// =========================================================================

class WhatsAppGroupDetailScreen extends StatefulWidget {
  final User user;
  final String groupId;
  final String groupName;
  final String? avatarBase64;

  const WhatsAppGroupDetailScreen({
    super.key,
    required this.user,
    required this.groupId,
    required this.groupName,
    this.avatarBase64,
  });

  @override
  State<WhatsAppGroupDetailScreen> createState() =>
      _WhatsAppGroupDetailScreenState();

  static void showExpenseDetailSheetStatic({
    required BuildContext context,
    required FirebaseFirestore db,
    required String groupId,
    required String currentUid,
    required String expenseId,
    required Map<String, dynamic> expenseData,
    required List<String> members,
    required bool isCurrentUserAdmin,
    required String currencySymbol,
  }) {
    final String title = (expenseData['title'] as String?) ?? 'Expense';
    final double amount = (expenseData['amount'] as num?)?.toDouble() ?? 0.0;
    final String categoryName =
        (expenseData['category'] as String?) ?? 'General';
    final String note = (expenseData['note'] as String?) ?? '';
    final String? paidById = expenseData['paidById'] as String?;
    final String? paidByRaw = expenseData['paidBy'] as String?;
    final bool isPaid = expenseData['isPaid'] ?? false;
    final Map<String, dynamic>? customSplits =
    expenseData['customSplits'] is Map
        ? Map<String, dynamic>.from(expenseData['customSplits'])
        : null;
    final Timestamp? ts = expenseData['timestamp'] as Timestamp?;
    final String formattedDate = ts != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(ts.toDate())
        : 'Recorded recently';

    final catMeta = _getCategoryMeta(categoryName);
    final int splitCount = members.isNotEmpty ? members.length : 1;
    final double defaultPerPersonShare = amount / splitCount;
    final bool canDelete =
        isCurrentUserAdmin || (paidById != null && paidById == currentUid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _ShareTheme.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: catMeta.color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child:
                      Icon(catMeta.icon, color: catMeta.color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catMeta.name,
                            style: TextStyle(
                              color: catMeta.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            style: const TextStyle(
                              color: _ShareTheme.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$currencySymbol${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _ShareTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Paid By',
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13)),
                          _ResolvedMemberNameText(
                            uid: paidById,
                            fallbackName: paidByRaw,
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Date',
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13)),
                          Text(formattedDate,
                              style: const TextStyle(
                                  color: _ShareTheme.textPrimary,
                                  fontSize: 12.5)),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 22),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Split Breakdown',
                          style: TextStyle(
                              color: _ShareTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...members.map((mUid) {
                        final double shareAmt = customSplits != null &&
                            customSplits.containsKey(mUid)
                            ? (customSplits[mUid] as num).toDouble()
                            : defaultPerPersonShare;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: _ResolvedMemberNameText(
                                  uid: mUid,
                                  style: const TextStyle(
                                      color: _ShareTheme.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                              Text(
                                '$currencySymbol${shareAmt.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: _ShareTheme.mintBright,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(color: Colors.white10, height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Payment Status',
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPaid
                                  ? Colors.green.withOpacity(0.2)
                                  : _ShareTheme.mint,
                              foregroundColor:
                              isPaid ? Colors.greenAccent : Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              final bool newStatus = !isPaid;
                              await db
                                  .collection('groups')
                                  .doc(groupId)
                                  .collection('expenses')
                                  .doc(expenseId)
                                  .update({'isPaid': newStatus});

                              if (context.mounted) Navigator.pop(sheetContext);
                            },
                            icon: Icon(
                              isPaid
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                            ),
                            label: Text(
                              isPaid ? 'Settled / Paid' : 'Mark as Paid',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(note,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13.5)),
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.redAccent.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await db
                            .collection('groups')
                            .doc(groupId)
                            .collection('expenses')
                            .doc(expenseId)
                            .delete();
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      label: const Text(
                        'Delete Expense',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatsAppGroupDetailScreenState extends State<WhatsAppGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _expenseTitleController = TextEditingController();
  final TextEditingController _expenseAmountController =
  TextEditingController(text: '00.00');
  final TextEditingController _expenseNoteController = TextEditingController();

  final Map<String, Future<_MemberProfile>> _profileFutures = {};
  int _lastSeenMessageCount = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _GroupPhoneNotifier.instance.activeOpenGroupId = widget.groupId;
    _markGroupAsRead();
  }

  @override
  void dispose() {
    if (_GroupPhoneNotifier.instance.activeOpenGroupId == widget.groupId) {
      _GroupPhoneNotifier.instance.activeOpenGroupId = null;
    }
    _tabController.dispose();
    _msgController.dispose();
    _expenseTitleController.dispose();
    _expenseAmountController.dispose();
    _expenseNoteController.dispose();
    super.dispose();
  }

  Future<void> _markGroupAsRead() async {
    try {
      await _db.collection('groups').doc(widget.groupId).set({
        'lastReadAt': {
          widget.user.uid: FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _updateGroupLastMessage({
    required String text,
    required String senderName,
  }) async {
    try {
      await _db.collection('groups').doc(widget.groupId).set({
        'lastMessage': text,
        'lastMessageSender': senderName,
        'lastMessageSenderId': widget.user.uid,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastReadAt': {
          widget.user.uid: FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _postFinancialSystemLog(String summaryText) async {
    final displayName = await _getCurrentUserDisplayName();
    await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .add({
      'text': summaryText,
      'senderName': displayName,
      'senderId': widget.user.uid,
      'isSystem': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _updateGroupLastMessage(
      text: summaryText,
      senderName: displayName,
    );
  }

  Uint8List? _decodeBase64Safe(String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    try {
      final cleanBase64 = rawBase64.contains(',')
          ? rawBase64.split(',').last.trim()
          : rawBase64.trim();
      return base64Decode(cleanBase64);
    } catch (_) {
      return null;
    }
  }

  Future<String> _getCurrentUserDisplayName() async {
    final profile = await _getCachedMemberProfile(
      uid: widget.user.uid,
      emailOrFallback: widget.user.displayName ?? widget.user.email,
    );
    return profile.displayName;
  }

  Future<_MemberProfile> _fetchMemberProfileFromDb(
      {String? uid, String? emailOrFallback}) async {
    Map<String, dynamic>? userData;
    String? resolvedUid = uid;

    if (uid != null && uid.isNotEmpty) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          userData = doc.data();
        }
      } catch (_) {}
    }

    if (userData == null &&
        emailOrFallback != null &&
        emailOrFallback.contains('@')) {
      try {
        final query = await _db
            .collection('users')
            .where('email', isEqualTo: emailOrFallback.trim())
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          userData = query.docs.first.data();
          resolvedUid ??= query.docs.first.id;
        }
      } catch (_) {}
    }

    if (userData != null) {
      final String? dbName = userData['displayName'] as String?;
      final String? dbEmail = userData['email'] as String?;
      final String? dbBio =
      (userData['bio'] ?? userData['about'] ?? userData['status'])
      as String?;
      final String? dbPhone =
      (userData['phone'] ?? userData['phoneNumber']) as String?;
      final String? dbPhoto = userData['profilePicture'] as String?;
      final String resolvedName = (dbName != null && dbName.trim().isNotEmpty)
          ? dbName.trim()
          : (emailOrFallback != null && emailOrFallback.contains('@')
          ? emailOrFallback.split('@').first
          : (emailOrFallback?.trim().isNotEmpty == true
          ? emailOrFallback!.trim()
          : 'Member'));

      return _MemberProfile(
        uid: resolvedUid,
        displayName: resolvedName,
        email: dbEmail,
        bio: dbBio,
        phone: dbPhone,
        photoBytes: _decodeBase64Safe(dbPhoto),
      );
    }

    final String fallbackName;
    if (emailOrFallback != null && emailOrFallback.contains('@')) {
      fallbackName = emailOrFallback.split('@').first;
    } else if (emailOrFallback != null && emailOrFallback.trim().isNotEmpty) {
      fallbackName = emailOrFallback.trim();
    } else {
      fallbackName = 'Member';
    }

    return _MemberProfile(
      uid: resolvedUid,
      displayName: fallbackName,
      email: emailOrFallback,
    );
  }

  Future<_MemberProfile> _getCachedMemberProfile(
      {String? uid, String? emailOrFallback}) {
    final String cacheKey = (uid != null && uid.isNotEmpty)
        ? 'uid:$uid'
        : 'fallback:${emailOrFallback ?? ''}';

    return _profileFutures.putIfAbsent(
      cacheKey,
          () => _fetchMemberProfileFromDb(
          uid: uid, emailOrFallback: emailOrFallback),
    );
  }

  void _openMemberProfile({
    String? uid,
    String? emailOrFallback,
    required String currencySymbol,
    required List<String> members,
    required bool isCurrentUserAdmin,
  }) {
    _showGroupMemberProfileSheet(
      context: context,
      db: _db,
      groupId: widget.groupId,
      currentUid: widget.user.uid,
      targetUid: uid,
      fallbackName: emailOrFallback,
      prefetchedProfile: null,
      currencySymbol: currencySymbol,
      members: members,
      isCurrentUserAdmin: isCurrentUserAdmin,
    );
  }

  Widget _buildDbDisplayNameText({
    String? uid,
    String? emailOrFallback,
    String prefix = '',
    required TextStyle style,
    bool tappable = false,
    String currencySymbol = 'RM',
    List<String> members = const [],
    bool isCurrentUserAdmin = false,
  }) {
    return FutureBuilder<_MemberProfile>(
      future:
      _getCachedMemberProfile(uid: uid, emailOrFallback: emailOrFallback),
      builder: (context, snapshot) {
        final String name = snapshot.data?.displayName ??
            (emailOrFallback != null && !emailOrFallback.contains('@')
                ? emailOrFallback
                : '...');
        final textWidget = Text(
          '$prefix$name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

        if (!tappable) return textWidget;
        return GestureDetector(
          onTap: () => _openMemberProfile(
            uid: snapshot.data?.uid ?? uid,
            emailOrFallback: emailOrFallback,
            currencySymbol: currencySymbol,
            members: members,
            isCurrentUserAdmin: isCurrentUserAdmin,
          ),
          child: textWidget,
        );
      },
    );
  }

  Widget _buildUserChatAvatar({
    String? uid,
    String? emailOrFallback,
    double radius = 16,
    required String currencySymbol,
    required List<String> members,
    required bool isCurrentUserAdmin,
  }) {
    final String fallbackInitial =
    (emailOrFallback != null && emailOrFallback.trim().isNotEmpty)
        ? emailOrFallback.trim()[0].toUpperCase()
        : 'M';

    return FutureBuilder<_MemberProfile>(
      future:
      _getCachedMemberProfile(uid: uid, emailOrFallback: emailOrFallback),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final Uint8List? photoBytes = profile?.photoBytes;
        final String initial =
        (profile != null && profile.displayName.isNotEmpty)
            ? profile.displayName[0].toUpperCase()
            : fallbackInitial;

        final avatar = photoBytes != null
            ? CircleAvatar(
          radius: radius,
          backgroundColor: _ShareTheme.accent.withOpacity(0.25),
          backgroundImage: MemoryImage(photoBytes),
        )
            : CircleAvatar(
          radius: radius,
          backgroundColor: _ShareTheme.accent.withOpacity(0.25),
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: radius * 0.78,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        return GestureDetector(
          onTap: () => _openMemberProfile(
            uid: profile?.uid ?? uid,
            emailOrFallback: emailOrFallback,
            currencySymbol: currencySymbol,
            members: members,
            isCurrentUserAdmin: isCurrentUserAdmin,
          ),
          child: avatar,
        );
      },
    );
  }

  void _showAdjustBudgetAndIncomeModal({
    required double currentBudget,
    required double currentIncome,
    required String currencySymbol,
  }) {
    final budgetController = TextEditingController(
      text: _Currency00Dot00Formatter.formatFromDouble(currentBudget),
    );
    final incomeController = TextEditingController(
      text: _Currency00Dot00Formatter.formatFromDouble(currentIncome),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _ShareTheme.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 22,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set Budget & Income',
                style: TextStyle(
                  color: _ShareTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter numbers only (format: 00.00)',
                style:
                TextStyle(color: _ShareTheme.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: budgetController,
                keyboardType: TextInputType.number,
                inputFormatters: [_Currency00Dot00Formatter()],
                style: const TextStyle(
                  color: _ShareTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'Spending Budget ($currencySymbol)',
                  labelStyle: const TextStyle(
                      color: _ShareTheme.textMuted, fontSize: 14),
                  prefixText: '$currencySymbol ',
                  prefixStyle: const TextStyle(
                      color: _ShareTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                    const BorderSide(color: _ShareTheme.accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: incomeController,
                keyboardType: TextInputType.number,
                inputFormatters: [_Currency00Dot00Formatter()],
                style: const TextStyle(
                  color: _ShareTheme.mintBright,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'Group Income / Pool ($currencySymbol)',
                  labelStyle: const TextStyle(
                      color: _ShareTheme.textMuted, fontSize: 14),
                  prefixText: '$currencySymbol ',
                  prefixStyle: const TextStyle(
                      color: _ShareTheme.mintBright,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                    const BorderSide(color: _ShareTheme.mint, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ShareTheme.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final double newBudget =
                    _Currency00Dot00Formatter.parseToDouble(
                        budgetController.text);
                    final double newIncome =
                    _Currency00Dot00Formatter.parseToDouble(
                        incomeController.text);

                    await _db.collection('groups').doc(widget.groupId).set({
                      'budget': newBudget,
                      'income': newIncome,
                    }, SetOptions(merge: true));

                    final displayName = await _getCurrentUserDisplayName();
                    final List<String> changes = [];
                    if ((newBudget - currentBudget).abs() > 0.009) {
                      changes.add(
                          'budget to $currencySymbol${newBudget.toStringAsFixed(2)}');
                    }
                    if ((newIncome - currentIncome).abs() > 0.009) {
                      changes.add(
                          'income to $currencySymbol${newIncome.toStringAsFixed(2)}');
                    }

                    if (changes.isNotEmpty) {
                      await _postFinancialSystemLog(
                        '💰 $displayName updated ${changes.join(' & ')}',
                      );
                    }

                    if (mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: _ShareTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddExpenseModal(String currencySymbol, List<String> groupMembers) {
    String selectedCategory = _kGroupExpenseCategories.first.name;
    _expenseAmountController.text = '00.00';
    bool isCustomSplit = false;
    String? modalErrorText;

    final Map<String, TextEditingController> customSplitControllers = {
      for (final m in groupMembers) m: TextEditingController(text: '00.00')
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _ShareTheme.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Expense',
                  style: TextStyle(
                      color: _ShareTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _expenseTitleController,
                  style: const TextStyle(color: _ShareTheme.textPrimary),
                  onChanged: (_) {
                    if (modalErrorText != null) {
                      setModalState(() => modalErrorText = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'What was it for?',
                    hintText: 'e.g. Dinner, Groceries, Grab',
                    hintStyle: const TextStyle(color: Colors.white24),
                    labelStyle: const TextStyle(color: _ShareTheme.textMuted),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: _ShareTheme.accent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _expenseAmountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_Currency00Dot00Formatter()],
                  style: const TextStyle(
                    color: _ShareTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount ($currencySymbol)',
                    labelStyle: const TextStyle(
                        color: _ShareTheme.textMuted, fontSize: 14),
                    prefixText: '$currencySymbol ',
                    prefixStyle: const TextStyle(
                        color: _ShareTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: _ShareTheme.accent, width: 2),
                    ),
                  ),
                  onChanged: (_) => setModalState(() => modalErrorText = null),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Category',
                  style: TextStyle(
                      color: _ShareTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kGroupExpenseCategories.map((cat) {
                    final bool isSelected = selectedCategory == cat.name;
                    return ChoiceChip(
                      selected: isSelected,
                      backgroundColor: _ShareTheme.card,
                      selectedColor: cat.color.withOpacity(0.28),
                      side: BorderSide(
                        color: isSelected ? cat.color : Colors.white12,
                      ),
                      avatar: Icon(cat.icon, size: 16, color: cat.color),
                      label: Text(
                        cat.name,
                        style: TextStyle(
                          color: isSelected
                              ? _ShareTheme.textPrimary
                              : _ShareTheme.textMuted,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      onSelected: (_) {
                        setModalState(() => selectedCategory = cat.name);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Split Type',
                      style: TextStyle(
                          color: _ShareTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Text(
                          isCustomSplit ? 'Custom Amounts' : 'Equal Split',
                          style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: isCustomSplit,
                          activeColor: _ShareTheme.accent,
                          onChanged: (val) {
                            setModalState(() {
                              isCustomSplit = val;
                              modalErrorText = null;
                              if (!val) {
                                for (var c in customSplitControllers.values) {
                                  c.text = '00.00';
                                }
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                if (isCustomSplit) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: modalErrorText != null
                            ? Colors.redAccent.withOpacity(0.7)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Specify how much each member owes:',
                          style: TextStyle(
                              color: _ShareTheme.textMuted, fontSize: 11.5),
                        ),
                        const SizedBox(height: 10),
                        ...groupMembers.map((mUid) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _buildDbDisplayNameText(
                                    uid: mUid,
                                    currencySymbol: currencySymbol,
                                    style: const TextStyle(
                                        color: _ShareTheme.textPrimary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: customSplitControllers[mUid],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      _Currency00Dot00Formatter()
                                    ],
                                    style: const TextStyle(
                                        color: _ShareTheme.textPrimary,
                                        fontSize: 13),
                                    onChanged: (_) {
                                      if (modalErrorText != null) {
                                        setModalState(
                                                () => modalErrorText = null);
                                      }
                                    },
                                    decoration: InputDecoration(
                                      prefixText: '$currencySymbol ',
                                      prefixStyle: const TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                      isDense: true,
                                      contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Colors.white24),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: _ShareTheme.accent),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _expenseNoteController,
                  maxLines: 2,
                  style: const TextStyle(
                      color: _ShareTheme.textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: 'Note (Optional)',
                    hintText: 'Add a short note...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    labelStyle: const TextStyle(color: _ShareTheme.textMuted),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: _ShareTheme.accent, width: 2),
                    ),
                  ),
                ),

                // --- IN-POPUP ERROR BANNER ---
                if (modalErrorText != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.65),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modalErrorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ShareTheme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      final title = _expenseTitleController.text.trim();
                      final amount = _Currency00Dot00Formatter.parseToDouble(
                          _expenseAmountController.text);
                      final note = _expenseNoteController.text.trim();

                      if (title.isEmpty) {
                        setModalState(() {
                          modalErrorText =
                          'Please enter what this expense was for.';
                        });
                        return;
                      }

                      if (amount <= 0) {
                        setModalState(() {
                          modalErrorText =
                          'Please enter an expense amount greater than ${currencySymbol}0.00.';
                        });
                        return;
                      }

                      Map<String, double>? customSplitsMap;
                      if (isCustomSplit) {
                        customSplitsMap = {};
                        double sumCustom = 0.0;
                        for (final entry in customSplitControllers.entries) {
                          final val = _Currency00Dot00Formatter.parseToDouble(
                              entry.value.text);
                          customSplitsMap[entry.key] = val;
                          sumCustom += val;
                        }

                        if ((sumCustom - amount).abs() > 0.02) {
                          setModalState(() {
                            modalErrorText =
                            'Custom splits total ($currencySymbol${sumCustom.toStringAsFixed(2)}) must equal the expense amount ($currencySymbol${amount.toStringAsFixed(2)}).';
                          });
                          return;
                        }
                      }

                      setModalState(() => modalErrorText = null);

                      final String displayName =
                      await _getCurrentUserDisplayName();
                      final String systemSummary =
                          '💵 $displayName added shared expense: "$title" ($currencySymbol${amount.toStringAsFixed(2)} • $selectedCategory)';

                      await _db
                          .collection('groups')
                          .doc(widget.groupId)
                          .collection('expenses')
                          .add({
                        'title': title,
                        'amount': amount,
                        'category': selectedCategory,
                        'note': note,
                        'paidBy': displayName,
                        'paidById': widget.user.uid,
                        'isPaid': false,
                        'customSplits': customSplitsMap,
                        'timestamp': FieldValue.serverTimestamp(),
                      });

                      await _db
                          .collection('groups')
                          .doc(widget.groupId)
                          .collection('messages')
                          .add({
                        'text': systemSummary,
                        'senderName': displayName,
                        'senderId': widget.user.uid,
                        'isSystem': true,
                        'timestamp': FieldValue.serverTimestamp(),
                      });

                      await _updateGroupLastMessage(
                        text: systemSummary,
                        senderName: displayName,
                      );

                      _expenseTitleController.clear();
                      _expenseAmountController.text = '00.00';
                      _expenseNoteController.clear();
                      if (mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Save Expense',
                        style: TextStyle(
                            color: _ShareTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExpenseDetailSheet({
    required String expenseId,
    required Map<String, dynamic> expenseData,
    required List<String> members,
    required bool isCurrentUserAdmin,
    required String currencySymbol,
  }) {
    final String title = (expenseData['title'] as String?) ?? 'Expense';
    final double amount = (expenseData['amount'] as num?)?.toDouble() ?? 0.0;
    final String categoryName =
        (expenseData['category'] as String?) ?? 'General';
    final String note = (expenseData['note'] as String?) ?? '';
    final String? paidById = expenseData['paidById'] as String?;
    final String? paidByRaw = expenseData['paidBy'] as String?;
    final bool isPaid = expenseData['isPaid'] ?? false;
    final Map<String, dynamic>? customSplits =
    expenseData['customSplits'] is Map
        ? Map<String, dynamic>.from(expenseData['customSplits'])
        : null;
    final Timestamp? ts = expenseData['timestamp'] as Timestamp?;
    final String formattedDate = ts != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(ts.toDate())
        : 'Recorded recently';

    final catMeta = _getCategoryMeta(categoryName);
    final int splitCount = members.isNotEmpty ? members.length : 1;
    final double defaultPerPersonShare = amount / splitCount;
    final bool canDelete =
        isCurrentUserAdmin || (paidById != null && paidById == widget.user.uid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _ShareTheme.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: catMeta.color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child:
                      Icon(catMeta.icon, color: catMeta.color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catMeta.name,
                            style: TextStyle(
                              color: catMeta.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            style: const TextStyle(
                              color: _ShareTheme.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$currencySymbol${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _ShareTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Paid By',
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13)),
                          InkWell(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _openMemberProfile(
                                uid: paidById,
                                emailOrFallback: paidByRaw,
                                currencySymbol: currencySymbol,
                                members: members,
                                isCurrentUserAdmin: isCurrentUserAdmin,
                              );
                            },
                            child: Row(
                              children: [
                                _buildUserChatAvatar(
                                  uid: paidById,
                                  emailOrFallback: paidByRaw,
                                  radius: 13,
                                  currencySymbol: currencySymbol,
                                  members: members,
                                  isCurrentUserAdmin: isCurrentUserAdmin,
                                ),
                                const SizedBox(width: 8),
                                _buildDbDisplayNameText(
                                  uid: paidById,
                                  emailOrFallback: paidByRaw,
                                  currencySymbol: currencySymbol,
                                  members: members,
                                  isCurrentUserAdmin: isCurrentUserAdmin,
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Date',
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13)),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                                color: _ShareTheme.textPrimary,
                                fontSize: 12.5),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 22),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Split Breakdown',
                          style: TextStyle(
                              color: _ShareTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...members.map((mUid) {
                        final double shareAmt = customSplits != null &&
                            customSplits.containsKey(mUid)
                            ? (customSplits[mUid] as num).toDouble()
                            : defaultPerPersonShare;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildDbDisplayNameText(
                                uid: mUid,
                                currencySymbol: currencySymbol,
                                members: members,
                                isCurrentUserAdmin: isCurrentUserAdmin,
                                style: const TextStyle(
                                    color: _ShareTheme.textPrimary,
                                    fontSize: 13),
                              ),
                              Text(
                                '$currencySymbol${shareAmt.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: _ShareTheme.mintBright,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(color: Colors.white10, height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Payment Status',
                            style: TextStyle(
                                color: _ShareTheme.textMuted, fontSize: 13),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPaid
                                  ? Colors.green.withOpacity(0.2)
                                  : _ShareTheme.mint,
                              foregroundColor:
                              isPaid ? Colors.greenAccent : Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              final bool newStatus = !isPaid;

                              await _db
                                  .collection('groups')
                                  .doc(widget.groupId)
                                  .collection('expenses')
                                  .doc(expenseId)
                                  .update({'isPaid': newStatus});

                              final actor =
                              await _getCurrentUserDisplayName();
                              await _postFinancialSystemLog(
                                newStatus
                                    ? '✅ $actor marked "$title" ($currencySymbol${amount.toStringAsFixed(2)}) as Settled/Paid'
                                    : '⏳ $actor marked "$title" as Unpaid',
                              );

                              if (mounted) Navigator.pop(sheetContext);
                            },
                            icon: Icon(
                              isPaid
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                            ),
                            label: Text(
                              isPaid ? 'Settled / Paid' : 'Mark as Paid',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      note,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.redAccent.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _db
                            .collection('groups')
                            .doc(widget.groupId)
                            .collection('expenses')
                            .doc(expenseId)
                            .delete();
                        final actor = await _getCurrentUserDisplayName();
                        await _postFinancialSystemLog(
                          '🗑️ $actor removed expense "$title" ($currencySymbol${amount.toStringAsFixed(2)})',
                        );
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      label: const Text(
                        'Delete Expense',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarAvatar(String? liveAvatarBase64, String liveGroupName) {
    final bytes = _decodeBase64Safe(liveAvatarBase64);
    if (bytes != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: _ShareTheme.accent.withOpacity(0.25),
        backgroundImage: MemoryImage(bytes),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: _ShareTheme.accent.withOpacity(0.25),
      child: Text(
        liveGroupName.isNotEmpty ? liveGroupName[0].toUpperCase() : 'G',
        style: const TextStyle(
            color: _ShareTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  void _openGroupInfoPage(String currentGroupName, String? currentAvatarBase64,
      String currencySymbol) {
    Navigator.push(
      context,
      _SmoothSlidePageRoute(
        page: WhatsAppGroupInfoScreen(
          user: widget.user,
          groupId: widget.groupId,
          initialGroupName: currentGroupName,
          initialAvatarBase64: currentAvatarBase64,
          currencySymbol: currencySymbol,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final String currencySymbol = _resolveCurrencySymbol(userData);

        return Scaffold(
          backgroundColor: _ShareTheme.background,
          appBar: AppBar(
            backgroundColor: _ShareTheme.header,
            elevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _ShareTheme.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('groups').doc(widget.groupId).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final String liveGroupName =
                    (data?['name'] as String?) ?? widget.groupName;
                final String? liveAvatarBase64 = data != null
                    ? (data['avatarBase64'] as String?)
                    : widget.avatarBase64;
                final List members = (data?['members'] as List?) ?? [];

                return InkWell(
                  onTap: () => _openGroupInfoPage(
                      liveGroupName, liveAvatarBase64, currencySymbol),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 6.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        _buildAppBarAvatar(liveAvatarBase64, liveGroupName),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                liveGroupName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ShareTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                members.isNotEmpty
                                    ? '${members.length} ${members.length == 1 ? 'member' : 'members'} • Tap for group info'
                                    : 'Tap for group info',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _ShareTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: _ShareTheme.accent,
              indicatorWeight: 3,
              labelColor: _ShareTheme.accent,
              unselectedLabelColor: _ShareTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'CHATS'),
                Tab(text: 'EXPENSES & BUDGET'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // ===============================================================
              // TAB 1: GROUP CHAT INTERFACE
              // ===============================================================
              Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _db
                          .collection('groups')
                          .doc(widget.groupId)
                          .collection('messages')
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: _ShareTheme.accent));
                        }
                        final messages = snapshot.data!.docs;

                        if (messages.length != _lastSeenMessageCount) {
                          _lastSeenMessageCount = messages.length;
                          if (messages.isNotEmpty) {
                            _markGroupAsRead();
                          }
                        }

                        if (messages.isEmpty) {
                          return const Center(
                            child: Text(
                              'No messages yet.\nSay hi or add a shared expense!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _ShareTheme.textMuted, fontSize: 13),
                            ),
                          );
                        }

                        return ListView.builder(
                          reverse: true,
                          itemCount: messages.length,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          itemBuilder: (context, index) {
                            final msg =
                            messages[index].data() as Map<String, dynamic>;
                            final String? senderId = msg['senderId'] as String?;
                            final String? fallbackSender =
                            (msg['senderEmail'] ?? msg['senderName'])
                            as String?;
                            final bool isMe = (senderId != null &&
                                senderId == widget.user.uid) ||
                                (msg['senderEmail'] != null &&
                                    msg['senderEmail'] == widget.user.email);
                            final bool isSystem = msg['isSystem'] ?? false;

                            if (isSystem) {
                              return Center(
                                child: Container(
                                  margin:
                                  const EdgeInsets.symmetric(vertical: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _ShareTheme.header,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    msg['text'] ?? '',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              );
                            }

                            bool isFirstInSequence = true;
                            if (index + 1 < messages.length) {
                              final prevMsg = messages[index + 1].data()
                              as Map<String, dynamic>;
                              final bool prevIsSystem =
                                  prevMsg['isSystem'] ?? false;
                              if (!prevIsSystem) {
                                final String? prevSenderId =
                                prevMsg['senderId'] as String?;
                                final String? prevFallback =
                                (prevMsg['senderEmail'] ??
                                    prevMsg['senderName']) as String?;
                                final bool sameSender =
                                (senderId != null && senderId.isNotEmpty)
                                    ? senderId == prevSenderId
                                    : (fallbackSender != null &&
                                    fallbackSender == prevFallback);
                                if (sameSender) {
                                  isFirstInSequence = false;
                                }
                              }
                            }

                            if (isMe) {
                              return Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  constraints: BoxConstraints(
                                      maxWidth:
                                      MediaQuery.of(context).size.width *
                                          0.75),
                                  margin: EdgeInsets.only(
                                    top: isFirstInSequence ? 6 : 2,
                                    bottom: 2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _ShareTheme.accent,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: Radius.circular(
                                          isFirstInSequence ? 14 : 4),
                                      bottomLeft: const Radius.circular(14),
                                      bottomRight: Radius.zero,
                                    ),
                                  ),
                                  child: Text(
                                    msg['text'] ?? '',
                                    style: const TextStyle(
                                        color: _ShareTheme.textPrimary,
                                        fontSize: 14.5),
                                  ),
                                ),
                              );
                            }

                            return Padding(
                              padding: EdgeInsets.only(
                                top: isFirstInSequence ? 6 : 2,
                                bottom: 2,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  if (isFirstInSequence)
                                    StreamBuilder<DocumentSnapshot>(
                                      stream: _db
                                          .collection('groups')
                                          .doc(widget.groupId)
                                          .snapshots(),
                                      builder: (context, groupDocSnap) {
                                        final groupData = groupDocSnap.data
                                            ?.data()
                                        as Map<String, dynamic>? ??
                                            {};
                                        final List<String> membersList =
                                        ((groupData['members'] as List?) ??
                                            [])
                                            .map((e) => e.toString())
                                            .toList();
                                        final List<String> adminsList =
                                        ((groupData['admins'] as List?) ??
                                            [])
                                            .map((e) => e.toString())
                                            .toList();
                                        final bool isAdminVal = adminsList
                                            .contains(widget.user.uid) ||
                                            groupData['createdBy'] ==
                                                widget.user.uid;

                                        return _buildUserChatAvatar(
                                          uid: senderId,
                                          emailOrFallback: fallbackSender,
                                          radius: 16,
                                          currencySymbol: currencySymbol,
                                          members: membersList,
                                          isCurrentUserAdmin: isAdminVal,
                                        );
                                      },
                                    )
                                  else
                                    const SizedBox(width: 32),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.70,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _ShareTheme.card,
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(
                                              isFirstInSequence ? 4 : 14),
                                          topRight: const Radius.circular(14),
                                          bottomLeft: Radius.zero,
                                          bottomRight:
                                          const Radius.circular(14),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          if (isFirstInSequence)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 3.0),
                                              child: StreamBuilder<
                                                  DocumentSnapshot>(
                                                stream: _db
                                                    .collection('groups')
                                                    .doc(widget.groupId)
                                                    .snapshots(),
                                                builder:
                                                    (context, groupDocSnap) {
                                                  final groupData = groupDocSnap
                                                      .data
                                                      ?.data()
                                                  as Map<String,
                                                      dynamic>? ??
                                                      {};
                                                  final List<String>
                                                  membersList =
                                                  ((groupData['members']
                                                  as List?) ??
                                                      [])
                                                      .map((e) =>
                                                      e.toString())
                                                      .toList();
                                                  final List<String>
                                                  adminsList =
                                                  ((groupData['admins']
                                                  as List?) ??
                                                      [])
                                                      .map((e) =>
                                                      e.toString())
                                                      .toList();
                                                  final bool isAdminVal =
                                                      adminsList.contains(widget
                                                          .user.uid) ||
                                                          groupData[
                                                          'createdBy'] ==
                                                              widget.user.uid;

                                                  return _buildDbDisplayNameText(
                                                    uid: senderId,
                                                    emailOrFallback:
                                                    fallbackSender,
                                                    tappable: true,
                                                    currencySymbol:
                                                    currencySymbol,
                                                    members: membersList,
                                                    isCurrentUserAdmin:
                                                    isAdminVal,
                                                    style: const TextStyle(
                                                      color: Colors.cyanAccent,
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                      FontWeight.bold,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          Text(
                                            msg['text'] ?? '',
                                            style: const TextStyle(
                                                color: _ShareTheme.textPrimary,
                                                fontSize: 14.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Chat Input Bar
                  StreamBuilder<DocumentSnapshot>(
                    stream:
                    _db.collection('groups').doc(widget.groupId).snapshots(),
                    builder: (context, groupSnap) {
                      final groupMembers = ((groupSnap.data?.data()
                      as Map<String, dynamic>?)?['members']
                      as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                          [];

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        color: _ShareTheme.background,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: _ShareTheme.header,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _msgController,
                                        style: const TextStyle(
                                            color: _ShareTheme.textPrimary),
                                        decoration: const InputDecoration(
                                          hintText: 'Type a message...',
                                          hintStyle: TextStyle(
                                              color: _ShareTheme.textMuted),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Add Expense',
                                      icon: const Icon(Icons.add_card_outlined,
                                          color: Colors.cyanAccent),
                                      onPressed: () => _showAddExpenseModal(
                                          currencySymbol, groupMembers),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: _ShareTheme.accent,
                              child: IconButton(
                                icon: const Icon(Icons.send,
                                    color: _ShareTheme.textPrimary, size: 20),
                                onPressed: () async {
                                  final text = _msgController.text.trim();
                                  if (text.isEmpty) return;

                                  _msgController.clear();
                                  final String displayName =
                                  await _getCurrentUserDisplayName();

                                  await _db
                                      .collection('groups')
                                      .doc(widget.groupId)
                                      .collection('messages')
                                      .add({
                                    'text': text,
                                    'senderName': displayName,
                                    'senderId': widget.user.uid,
                                    'isSystem': false,
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });

                                  await _updateGroupLastMessage(
                                    text: text,
                                    senderName: displayName,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),

              // ===============================================================
              // TAB 2: CLEAN BUDGET & EXPENSES TAB
              // ===============================================================
              StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('groups').doc(widget.groupId).snapshots(),
                builder: (context, groupSnapshot) {
                  if (!groupSnapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: _ShareTheme.accent));
                  }

                  final groupData =
                      groupSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final double groupBudget =
                      (groupData['budget'] as num?)?.toDouble() ?? 0.0;
                  final double groupIncome =
                      (groupData['income'] as num?)?.toDouble() ?? 0.0;
                  final List<String> members =
                  ((groupData['members'] as List?) ?? [])
                      .map((e) => e.toString())
                      .toList();
                  final List<String> admins =
                  ((groupData['admins'] as List?) ?? [])
                      .map((e) => e.toString())
                      .toList();
                  final bool isCurrentUserAdmin =
                      admins.contains(widget.user.uid) ||
                          groupData['createdBy'] == widget.user.uid;

                  return StreamBuilder<QuerySnapshot>(
                    stream: _db
                        .collection('groups')
                        .doc(widget.groupId)
                        .collection('expenses')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, expenseSnapshot) {
                      if (!expenseSnapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: _ShareTheme.accent));
                      }

                      final expenses = expenseSnapshot.data!.docs;

                      double totalSpent = 0.0;
                      final Map<String, double> paidByMember = {
                        for (final m in members) m: 0.0,
                      };
                      final Map<String, double> owedByMember = {
                        for (final m in members) m: 0.0,
                      };

                      for (var doc in expenses) {
                        final data = doc.data() as Map<String, dynamic>;
                        final double amt =
                            (data['amount'] as num?)?.toDouble() ?? 0.0;
                        totalSpent += amt;
                        final String? payer = data['paidById'] as String?;
                        if (payer != null) {
                          paidByMember[payer] =
                              (paidByMember[payer] ?? 0.0) + amt;
                        }

                        final Map<String, dynamic>? customSplits =
                        data['customSplits'] is Map
                            ? Map<String, dynamic>.from(
                            data['customSplits'])
                            : null;

                        if (customSplits != null && customSplits.isNotEmpty) {
                          customSplits.forEach((mId, shareVal) {
                            owedByMember[mId] = (owedByMember[mId] ?? 0.0) +
                                ((shareVal as num?)?.toDouble() ?? 0.0);
                          });
                        } else {
                          final double equalShare =
                          members.isNotEmpty ? amt / members.length : amt;
                          for (final m in members) {
                            owedByMember[m] =
                                (owedByMember[m] ?? 0.0) + equalShare;
                          }
                        }
                      }

                      final double effectiveLimit =
                      groupBudget > 0 ? groupBudget : groupIncome;
                      final double remaining = effectiveLimit - totalSpent;
                      final double progress = effectiveLimit > 0
                          ? (totalSpent / effectiveLimit).clamp(0.0, 1.0)
                          : 0.0;
                      final bool isOverLimit =
                          effectiveLimit > 0 && totalSpent > effectiveLimit;
                      final double fairShare = members.isNotEmpty
                          ? totalSpent / members.length
                          : totalSpent;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- 1. BALANCE OVERVIEW CARD ---
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _ShareTheme.card,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.08)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isOverLimit
                                            ? 'Over Budget By'
                                            : 'Remaining Balance',
                                        style: const TextStyle(
                                          color: _ShareTheme.textMuted,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () =>
                                            _showAdjustBudgetAndIncomeModal(
                                              currentBudget: groupBudget,
                                              currentIncome: groupIncome,
                                              currencySymbol: currencySymbol,
                                            ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _ShareTheme.accent
                                                .withOpacity(0.18),
                                            borderRadius:
                                            BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.edit_outlined,
                                                  color: Colors.cyanAccent,
                                                  size: 14),
                                              SizedBox(width: 4),
                                              Text(
                                                'Edit Budget',
                                                style: TextStyle(
                                                  color: Colors.cyanAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$currencySymbol${remaining.abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: isOverLimit
                                          ? Colors.redAccent
                                          : _ShareTheme.textPrimary,
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      backgroundColor: Colors.white10,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isOverLimit
                                            ? Colors.redAccent
                                            : _ShareTheme.mint,
                                      ),
                                    ),
                                  ),
                                  const Divider(
                                      color: Colors.white10, height: 26),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            const Text('Budget',
                                                style: TextStyle(
                                                    color:
                                                    _ShareTheme.textMuted,
                                                    fontSize: 12)),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$currencySymbol${groupBudget.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: _ShareTheme.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                          children: [
                                            const Text('Income',
                                                style: TextStyle(
                                                    color:
                                                    _ShareTheme.textMuted,
                                                    fontSize: 12)),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$currencySymbol${groupIncome.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: _ShareTheme.mintBright,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                          children: [
                                            const Text('Spent',
                                                style: TextStyle(
                                                    color:
                                                    _ShareTheme.textMuted,
                                                    fontSize: 12)),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$currencySymbol${totalSpent.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // --- 2. ACTION BUTTONS (ADD EXPENSE & MY PAID HISTORY) ---
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _ShareTheme.accent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(14)),
                                      ),
                                      onPressed: () => _showAddExpenseModal(
                                          currencySymbol, members),
                                      icon: const Icon(Icons.add_circle_outline,
                                          color: _ShareTheme.textPrimary,
                                          size: 18),
                                      label: const Text(
                                        'Add Expense',
                                        style: TextStyle(
                                          color: _ShareTheme.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: _ShareTheme.accent,
                                            width: 1.5),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(14)),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          _SmoothSlidePageRoute(
                                            page: MemberPaidExpensesScreen(
                                              currentUser: widget.user,
                                              targetUid: widget.user.uid,
                                              targetMemberName: 'You',
                                              groupId: widget.groupId,
                                              groupName: widget.groupName,
                                              members: members,
                                              isCurrentUserAdmin:
                                              isCurrentUserAdmin,
                                              currencySymbol: currencySymbol,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.receipt_outlined,
                                          color: Colors.cyanAccent, size: 18),
                                      label: const Text(
                                        'My Paid',
                                        style: TextStyle(
                                          color: _ShareTheme.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // --- 3. MEMBER BALANCES ---
                            if (members.isNotEmpty) ...[
                              const SizedBox(height: 22),
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Member Balances',
                                    style: TextStyle(
                                      color: _ShareTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Share: ~$currencySymbol${fairShare.toStringAsFixed(2)} each',
                                    style: const TextStyle(
                                        color: _ShareTheme.textMuted,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 108,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: members.length,
                                  separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                                  itemBuilder: (context, idx) {
                                    final mUid = members[idx];
                                    final paid = paidByMember[mUid] ?? 0.0;
                                    final owed = owedByMember[mUid] ?? 0.0;
                                    final net = paid - owed;

                                    final String statusLabel;
                                    final Color statusColor;
                                    if (net > 0.009) {
                                      statusLabel =
                                      'Gets back $currencySymbol${net.toStringAsFixed(2)}';
                                      statusColor = _ShareTheme.mintBright;
                                    } else if (net < -0.009) {
                                      statusLabel =
                                      'Owes $currencySymbol${net.abs().toStringAsFixed(2)}';
                                      statusColor = Colors.orangeAccent;
                                    } else {
                                      statusLabel = 'Settled up';
                                      statusColor = Colors.cyanAccent;
                                    }

                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _openMemberProfile(
                                            uid: mUid,
                                            currencySymbol: currencySymbol,
                                            members: members,
                                            isCurrentUserAdmin:
                                            isCurrentUserAdmin),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: 150,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: _ShareTheme.card,
                                            borderRadius:
                                            BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withOpacity(0.08)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  _buildUserChatAvatar(
                                                    uid: mUid,
                                                    radius: 13,
                                                    currencySymbol:
                                                    currencySymbol,
                                                    members: members,
                                                    isCurrentUserAdmin:
                                                    isCurrentUserAdmin,
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Expanded(
                                                    child:
                                                    _buildDbDisplayNameText(
                                                      uid: mUid,
                                                      currencySymbol:
                                                      currencySymbol,
                                                      members: members,
                                                      isCurrentUserAdmin:
                                                      isCurrentUserAdmin,
                                                      style: const TextStyle(
                                                        color: _ShareTheme
                                                            .textPrimary,
                                                        fontSize: 13,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                'Paid $currencySymbol${paid.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: _ShareTheme.textMuted,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                              Text(
                                                statusLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],

                            // --- 4. RECENT EXPENSES HEADER WITH "VIEW ALL" ---
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Recent Expenses (${expenses.length})',
                                  style: const TextStyle(
                                    color: _ShareTheme.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (expenses.isNotEmpty)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: const Size(50, 28),
                                      tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        _SmoothSlidePageRoute(
                                          page: AllGroupExpensesScreen(
                                            user: widget.user,
                                            groupId: widget.groupId,
                                            groupName: widget.groupName,
                                            members: members,
                                            isCurrentUserAdmin:
                                            isCurrentUserAdmin,
                                            currencySymbol: currencySymbol,
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'View All',
                                          style: TextStyle(
                                            color: Colors.cyanAccent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          color: Colors.cyanAccent,
                                          size: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (expenses.isEmpty)
                              Container(
                                width: double.infinity,
                                padding:
                                const EdgeInsets.symmetric(vertical: 32),
                                decoration: BoxDecoration(
                                  color: _ShareTheme.card.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text(
                                    'No expenses yet. Tap "Add Expense" above.',
                                    style: TextStyle(
                                        color: _ShareTheme.textMuted,
                                        fontSize: 13),
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount:
                                expenses.length > 3 ? 3 : expenses.length,
                                itemBuilder: (context, index) {
                                  final expDoc = expenses[index];
                                  final data =
                                  expDoc.data() as Map<String, dynamic>;
                                  final Timestamp? ts =
                                  data['timestamp'] as Timestamp?;
                                  final String formattedDate = ts != null
                                      ? DateFormat('MMM dd').format(ts.toDate())
                                      : 'Today';

                                  return _CleanExpenseCard(
                                    data: data,
                                    currencySymbol: currencySymbol,
                                    formattedDate: formattedDate,
                                    showPaidBy: true,
                                    amountColor: _ShareTheme.textPrimary,
                                    onTap: () => _showExpenseDetailSheet(
                                      expenseId: expDoc.id,
                                      expenseData: data,
                                      members: members,
                                      isCurrentUserAdmin: isCurrentUserAdmin,
                                      currencySymbol: currencySymbol,
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// =========================================================================
// GROUP INFO SCREEN
// =========================================================================

class WhatsAppGroupInfoScreen extends StatefulWidget {
  final User user;
  final String groupId;
  final String initialGroupName;
  final String? initialAvatarBase64;
  final String currencySymbol;

  const WhatsAppGroupInfoScreen({
    super.key,
    required this.user,
    required this.groupId,
    required this.initialGroupName,
    this.initialAvatarBase64,
    required this.currencySymbol,
  });

  @override
  State<WhatsAppGroupInfoScreen> createState() =>
      _WhatsAppGroupInfoScreenState();
}

class _WhatsAppGroupInfoScreenState extends State<WhatsAppGroupInfoScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  final Map<String, Future<_MemberProfile>> _memberProfileFutures = {};

  bool _isUpdatingIcon = false;

  Uint8List? _decodeBase64Safe(String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    try {
      final cleanBase64 = rawBase64.contains(',')
          ? rawBase64.split(',').last.trim()
          : rawBase64.trim();
      return base64Decode(cleanBase64);
    } catch (_) {
      return null;
    }
  }

  Future<_MemberProfile> _fetchMemberProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final String? dbName = data['displayName'] as String?;
        final String? dbEmail = data['email'] as String?;
        final String? dbBio =
        (data['bio'] ?? data['about'] ?? data['status']) as String?;
        final String? dbPhone =
        (data['phone'] ?? data['phoneNumber']) as String?;
        final String? dbPhoto = data['profilePicture'] as String?;

        final String name = (dbName != null && dbName.trim().isNotEmpty)
            ? dbName.trim()
            : (dbEmail != null && dbEmail.contains('@')
            ? dbEmail.split('@').first
            : 'Member');

        return _MemberProfile(
          uid: uid,
          displayName: name,
          email: dbEmail,
          bio: dbBio,
          phone: dbPhone,
          photoBytes: _decodeBase64Safe(dbPhoto),
        );
      }
    } catch (_) {}
    return _MemberProfile(uid: uid, displayName: 'Member');
  }

  Future<_MemberProfile> _getMemberProfile(String uid) {
    return _memberProfileFutures.putIfAbsent(
        uid, () => _fetchMemberProfile(uid));
  }

  Set<String> _resolveAdminSet(
      Map<String, dynamic> groupData, List<String> members) {
    final Set<String> admins = {};

    final dynamic rawAdmins = groupData['admins'];
    if (rawAdmins is List) {
      for (final item in rawAdmins) {
        if (item is String && item.isNotEmpty) {
          admins.add(item);
        }
      }
    }

    final String? createdBy = groupData['createdBy'] as String?;
    if (createdBy != null && createdBy.isNotEmpty) {
      admins.add(createdBy);
    }

    if (admins.isEmpty && members.isNotEmpty) {
      admins.add(members.first);
    }

    return admins;
  }

  Future<String> _getActorDisplayName() async {
    final profile = await _getMemberProfile(widget.user.uid);
    return profile.displayName;
  }

  Future<void> _postSystemLog(String text) async {
    final actorName = await _getActorDisplayName();
    await _db
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .add({
      'text': text,
      'senderName': actorName,
      'senderId': widget.user.uid,
      'isSystem': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _db.collection('groups').doc(widget.groupId).set({
      'lastMessage': text,
      'lastMessageSender': actorName,
      'lastMessageSenderId': widget.user.uid,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastReadAt': {
        widget.user.uid: FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<void> _changeGroupIcon() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 75,
    );

    if (pickedFile == null) return;

    setState(() => _isUpdatingIcon = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      await _db.collection('groups').doc(widget.groupId).update({
        'avatarBase64': base64Image,
      });

      final actorName = await _getActorDisplayName();
      await _postSystemLog('🖼️ $actorName changed the group icon');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group icon updated!'),
            backgroundColor: _ShareTheme.mint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update group icon: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingIcon = false);
    }
  }

  void _showEditGroupNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ShareTheme.header,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Group Name',
          style: TextStyle(
              color: _ShareTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: _ShareTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter group name',
            hintStyle: const TextStyle(color: _ShareTheme.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: _ShareTheme.accent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel',
                style: TextStyle(color: _ShareTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ShareTheme.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == currentName) {
                Navigator.pop(dialogContext);
                return;
              }

              await _db.collection('groups').doc(widget.groupId).update({
                'name': newName,
              });

              final actorName = await _getActorDisplayName();
              await _postSystemLog(
                  '✏️ $actorName changed the group name to "$newName"');

              if (mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save',
                style: TextStyle(
                    color: _ShareTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditBudgetAndIncomeDialog(
      double currentBudget, double currentIncome, String currencySymbol) {
    final budgetController = TextEditingController(
      text: _Currency00Dot00Formatter.formatFromDouble(currentBudget),
    );
    final incomeController = TextEditingController(
      text: _Currency00Dot00Formatter.formatFromDouble(currentIncome),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ShareTheme.header,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Budget & Income',
          style: TextStyle(
              color: _ShareTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: budgetController,
              keyboardType: TextInputType.number,
              inputFormatters: [_Currency00Dot00Formatter()],
              style: const TextStyle(
                  color: _ShareTheme.textPrimary, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Group Budget ($currencySymbol)',
                labelStyle: const TextStyle(color: _ShareTheme.textMuted),
                prefixText: '$currencySymbol ',
                prefixStyle: const TextStyle(color: _ShareTheme.textPrimary),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: _ShareTheme.accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: incomeController,
              keyboardType: TextInputType.number,
              inputFormatters: [_Currency00Dot00Formatter()],
              style: const TextStyle(
                  color: _ShareTheme.mintBright, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Group Income ($currencySymbol)',
                labelStyle: const TextStyle(color: _ShareTheme.textMuted),
                prefixText: '$currencySymbol ',
                prefixStyle: const TextStyle(color: _ShareTheme.mintBright),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: _ShareTheme.mint, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel',
                style: TextStyle(color: _ShareTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ShareTheme.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newBudget = _Currency00Dot00Formatter.parseToDouble(
                  budgetController.text);
              final newIncome = _Currency00Dot00Formatter.parseToDouble(
                  incomeController.text);

              await _db.collection('groups').doc(widget.groupId).set({
                'budget': newBudget,
                'income': newIncome,
              }, SetOptions(merge: true));

              final actorName = await _getActorDisplayName();
              await _postSystemLog(
                '💰 $actorName set budget to $currencySymbol${newBudget.toStringAsFixed(2)} & income to $currencySymbol${newIncome.toStringAsFixed(2)}',
              );

              if (mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save',
                style: TextStyle(
                    color: _ShareTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _grantAdminRole(
      String targetUid, String targetName, Set<String> currentAdmins) async {
    final updatedAdmins = {...currentAdmins, targetUid}.toList();
    await _db.collection('groups').doc(widget.groupId).update({
      'admins': updatedAdmins,
    });

    final actorName = await _getActorDisplayName();
    await _postSystemLog('👑 $actorName made $targetName a group admin');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetName is now an admin.')),
      );
    }
  }

  Future<void> _dismissAdminRole(
      String targetUid,
      String targetName,
      Set<String> currentAdmins,
      String? createdBy,
      ) async {
    if (currentAdmins.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('At least one admin must remain in the group.')),
        );
      }
      return;
    }

    final updatedAdmins =
    currentAdmins.where((id) => id != targetUid).toList();
    final Map<String, dynamic> updates = {'admins': updatedAdmins};

    if (createdBy == targetUid && updatedAdmins.isNotEmpty) {
      updates['createdBy'] = updatedAdmins.first;
    }

    await _db.collection('groups').doc(widget.groupId).update(updates);

    final actorName = await _getActorDisplayName();
    await _postSystemLog('ℹ️ $actorName dismissed $targetName as admin');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetName is no longer an admin.')),
      );
    }
  }

  Future<void> _removeMemberFromGroup(
      String targetUid,
      String targetName,
      Set<String> currentAdmins,
      String? createdBy,
      ) async {
    final updatedAdmins =
    currentAdmins.where((id) => id != targetUid).toList();
    final Map<String, dynamic> updates = {
      'members': FieldValue.arrayRemove([targetUid]),
      'admins': updatedAdmins,
    };

    if (createdBy == targetUid && updatedAdmins.isNotEmpty) {
      updates['createdBy'] = updatedAdmins.first;
    }

    await _db.collection('groups').doc(widget.groupId).update(updates);

    final actorName = await _getActorDisplayName();
    await _postSystemLog('🚪 $actorName removed $targetName from the group');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$targetName removed from group.')),
      );
    }
  }

  void _openMemberProfileAndActions({
    required String targetUid,
    required _MemberProfile? profile,
    required bool isMe,
    required bool targetIsAdmin,
    required bool isCurrentUserAdmin,
    required Set<String> currentAdmins,
    required String? createdBy,
    required List<String> members,
  }) {
    final String targetName = profile?.displayName ?? 'Member';

    Widget? adminControls;
    if (isCurrentUserAdmin && !isMe) {
      adminControls = Container(
        decoration: BoxDecoration(
          color: _ShareTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            if (!targetIsAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined,
                    color: _ShareTheme.mint),
                title: const Text(
                  'Make Group Admin',
                  style: TextStyle(
                      color: _ShareTheme.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _grantAdminRole(targetUid, targetName, currentAdmins);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.remove_moderator_outlined,
                    color: Colors.orangeAccent),
                title: const Text(
                  'Dismiss as Admin',
                  style: TextStyle(
                      color: Colors.orangeAccent, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _dismissAdminRole(
                      targetUid, targetName, currentAdmins, createdBy);
                },
              ),
            const Divider(color: Colors.white10, height: 1),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: Colors.redAccent),
              title: Text(
                'Remove $targetName',
                style: const TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _removeMemberFromGroup(
                    targetUid, targetName, currentAdmins, createdBy);
              },
            ),
          ],
        ),
      );
    }

    _showGroupMemberProfileSheet(
      context: context,
      db: _db,
      groupId: widget.groupId,
      currentUid: widget.user.uid,
      targetUid: targetUid,
      fallbackName: targetName,
      prefetchedProfile: profile,
      currencySymbol: widget.currencySymbol,
      members: members,
      isCurrentUserAdmin: isCurrentUserAdmin,
      isAdmin: targetIsAdmin,
      adminActionSection: adminControls,
    );
  }

  Future<void> _confirmLeaveGroup(Set<String> currentAdmins,
      List<String> members, String? createdBy) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ShareTheme.header,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Exit Group?',
          style: TextStyle(
              color: _ShareTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to leave this group?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel',
                style: TextStyle(color: _ShareTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Exit Group',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final actorName = await _getActorDisplayName();
    await _postSystemLog('👋 $actorName left the group');

    final remainingMembers =
    members.where((id) => id != widget.user.uid).toList();
    final updatedAdmins =
    currentAdmins.where((id) => id != widget.user.uid).toList();

    if (updatedAdmins.isEmpty && remainingMembers.isNotEmpty) {
      updatedAdmins.add(remainingMembers.first);
    }

    final Map<String, dynamic> updates = {
      'members': FieldValue.arrayRemove([widget.user.uid]),
      'admins': updatedAdmins,
    };

    if (createdBy == widget.user.uid && updatedAdmins.isNotEmpty) {
      updates['createdBy'] = updatedAdmins.first;
    }

    await _db.collection('groups').doc(widget.groupId).update(updates);

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('groups').doc(widget.groupId).snapshots(),
      builder: (context, snapshot) {
        final groupData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final String groupName =
            (groupData['name'] as String?) ?? widget.initialGroupName;
        final String? avatarBase64 = groupData.containsKey('avatarBase64')
            ? groupData['avatarBase64'] as String?
            : widget.initialAvatarBase64;
        final String inviteCode = (groupData['inviteCode'] as String?) ?? '';
        final double budget = (groupData['budget'] as num?)?.toDouble() ?? 0.0;
        final double income = (groupData['income'] as num?)?.toDouble() ?? 0.0;
        final String? createdBy = groupData['createdBy'] as String?;

        final List<String> members = ((groupData['members'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final Set<String> adminSet = _resolveAdminSet(groupData, members);
        final bool isCurrentUserAdmin = adminSet.contains(widget.user.uid);

        final List<String> sortedMembers = [...members]..sort((a, b) {
          if (a == widget.user.uid) return -1;
          if (b == widget.user.uid) return 1;
          final aAdmin = adminSet.contains(a);
          final bAdmin = adminSet.contains(b);
          if (aAdmin && !bAdmin) return -1;
          if (!aAdmin && bAdmin) return 1;
          return 0;
        });

        final Uint8List? groupAvatarBytes = _decodeBase64Safe(avatarBase64);

        return Scaffold(
          backgroundColor: _ShareTheme.background,
          appBar: AppBar(
            backgroundColor: _ShareTheme.header,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _ShareTheme.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Group Info',
              style: TextStyle(
                  color: _ShareTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                  decoration: const BoxDecoration(
                    color: _ShareTheme.header,
                    borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: isCurrentUserAdmin && !_isUpdatingIcon
                            ? _changeGroupIcon
                            : null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 108,
                              height: 108,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _ShareTheme.accent.withOpacity(0.75),
                                  width: 2.5,
                                ),
                              ),
                              child: ClipOval(
                                child: groupAvatarBytes != null
                                    ? Image.memory(
                                  groupAvatarBytes,
                                  width: 108,
                                  height: 108,
                                  fit: BoxFit.cover,
                                )
                                    : Container(
                                  color:
                                  _ShareTheme.accent.withOpacity(0.2),
                                  alignment: Alignment.center,
                                  child: Text(
                                    groupName.isNotEmpty
                                        ? groupName[0].toUpperCase()
                                        : 'G',
                                    style: const TextStyle(
                                      color: _ShareTheme.accent,
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_isUpdatingIcon)
                              Container(
                                width: 108,
                                height: 108,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                ),
                              ),
                            if (isCurrentUserAdmin)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _ShareTheme.accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _ShareTheme.header, width: 2),
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
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              groupName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _ShareTheme.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isCurrentUserAdmin) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: const Icon(Icons.edit_outlined,
                                  color: Colors.white70, size: 19),
                              onPressed: () =>
                                  _showEditGroupNameDialog(groupName),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${members.length} ${members.length == 1 ? 'member' : 'members'}',
                        style: const TextStyle(
                            color: _ShareTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _ShareTheme.accent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.vpn_key_outlined,
                                      color: _ShareTheme.accent, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Invite Code',
                                      style: TextStyle(
                                          color: _ShareTheme.textMuted,
                                          fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      inviteCode.isNotEmpty
                                          ? inviteCode
                                          : '------',
                                      style: const TextStyle(
                                        color: _ShareTheme.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (inviteCode.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded,
                                    color: Colors.cyanAccent, size: 20),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: inviteCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Invite code copied!')),
                                  );
                                },
                              ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 22),
                        InkWell(
                          onTap: () => _showEditBudgetAndIncomeDialog(
                              budget, income, widget.currencySymbol),
                          borderRadius: BorderRadius.circular(10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _ShareTheme.mint.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: _ShareTheme.mint,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Budget & Income',
                                        style: TextStyle(
                                            color: _ShareTheme.textMuted,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Budget ${widget.currencySymbol}${budget.toStringAsFixed(2)} • Income ${widget.currencySymbol}${income.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: _ShareTheme.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Icon(Icons.edit_outlined,
                                  color: Colors.cyanAccent, size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 4.0),
                          child: Text(
                            'Members (${members.length})',
                            style: const TextStyle(
                              color: _ShareTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Divider(color: Colors.white10, height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sortedMembers.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Colors.white10,
                            height: 1,
                            indent: 68,
                          ),
                          itemBuilder: (context, index) {
                            final memberUid = sortedMembers[index];
                            final bool isMe = memberUid == widget.user.uid;
                            final bool isMemberAdmin =
                            adminSet.contains(memberUid);

                            return FutureBuilder<_MemberProfile>(
                              future: _getMemberProfile(memberUid),
                              builder: (context, profileSnap) {
                                final profile = profileSnap.data;
                                final String displayName =
                                    profile?.displayName ?? 'Loading...';
                                final String? email = profile?.email;
                                final Uint8List? photoBytes =
                                    profile?.photoBytes;
                                final String initial = displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'M';

                                return ListTile(
                                  onTap: () => _openMemberProfileAndActions(
                                    targetUid: memberUid,
                                    profile: profile,
                                    isMe: isMe,
                                    targetIsAdmin: isMemberAdmin,
                                    isCurrentUserAdmin: isCurrentUserAdmin,
                                    currentAdmins: adminSet,
                                    createdBy: createdBy,
                                    members: members,
                                  ),
                                  leading: photoBytes != null
                                      ? CircleAvatar(
                                    radius: 21,
                                    backgroundColor: _ShareTheme.accent
                                        .withOpacity(0.25),
                                    backgroundImage:
                                    MemoryImage(photoBytes),
                                  )
                                      : CircleAvatar(
                                    radius: 21,
                                    backgroundColor: _ShareTheme.accent
                                        .withOpacity(0.25),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    isMe
                                        ? '$displayName (You)'
                                        : displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _ShareTheme.textPrimary,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: email != null && email.isNotEmpty
                                      ? Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _ShareTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isMemberAdmin)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _ShareTheme.mint
                                                .withOpacity(0.15),
                                            borderRadius:
                                            BorderRadius.circular(6),
                                            border: Border.all(
                                              color: _ShareTheme.mint
                                                  .withOpacity(0.6),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Text(
                                            'Admin',
                                            style: TextStyle(
                                              color: _ShareTheme.mint,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: _ShareTheme.textMuted,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _ShareTheme.card,
                      borderRadius: BorderRadius.circular(18),
                      border:
                      Border.all(color: Colors.redAccent.withOpacity(0.25)),
                    ),
                    child: ListTile(
                      onTap: () =>
                          _confirmLeaveGroup(adminSet, members, createdBy),
                      leading: const Icon(Icons.exit_to_app_rounded,
                          color: Colors.redAccent),
                      title: const Text(
                        'Exit Group',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),
              ],
            ),
          ),
        );
      },
    );
  }
}