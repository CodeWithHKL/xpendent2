import 'dart:convert';
import 'dart:typed_data';
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

  /// Tracks whichever group chat is currently open on screen so we don't
  /// buzz the user while they are actively reading that group.
  String? activeOpenGroupId;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

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
    await ensureInitialized();

    // Seed existing timestamps on first load so old messages don't fire alerts
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

      // Only notify if this is a newer event than what we last processed
      if (previousMillis != null && msgMillis <= previousMillis) {
        continue;
      }
      _lastNotifiedMsgMillis[groupId] = msgMillis;

      final String? senderId = data['lastMessageSenderId'] as String?;
      if (senderId == null || senderId == currentUid) continue;

      // Skip if user is currently viewing this exact group chat
      if (activeOpenGroupId == groupId) continue;

      final String groupName = (data['name'] as String?) ?? 'Group Expense';
      final String senderName =
          (data['lastMessageSender'] as String?) ?? 'Member';
      final String rawMessage = (data['lastMessage'] as String?) ?? '';
      if (rawMessage.trim().isEmpty) continue;

      final bool isExpenseAlert = rawMessage.startsWith('💵') ||
          rawMessage.contains('added shared expense:');

      // Respect the user's Expense Notifications toggle for shared expenses
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
// REUSABLE BOTTOM NAV ICON WITH WHATSAPP-STYLE NEW MESSAGE INDICATOR
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
    this.activeColor = const Color(0xFF6C5CE7),
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

          // Trigger phone notification for any newly arrived message or expense
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

        final IconData displayIcon =
        (widget.isSelected || hasUnread) ? widget.activeIcon : widget.inactiveIcon;

        final Color displayColor = widget.isSelected
            ? widget.activeColor
            : (hasUnread ? const Color(0xFF00E676) : widget.inactiveColor);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: (!widget.isSelected && hasUnread)
                  ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              )
                  : null,
              child: Icon(
                displayIcon,
                color: displayColor,
                size: 24,
              ),
            ),
            if (hasUnread)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4.5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C897),
                    borderRadius: BorderRadius.circular(10),
                    border:
                    Border.all(color: const Color(0xFF132247), width: 1.5),
                  ),
                  constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadGroupsCount > 9 ? '9+' : '$unreadGroupsCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0F1626),
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
// MAIN SHARE SCREEN (GROUP LIST WITH LIVE MESSAGE PREVIEW)
// =========================================================================

class ShareScreen extends StatefulWidget {
  final User user;

  const ShareScreen({super.key, required this.user});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Color appBackground = Color(0xFF0F1626);
  static const Color appHeader = Color(0xFF132247);
  static const Color appCard = Color(0xFF1A2642);
  static const Color appAccent = Color(0xFF6C5CE7);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Colors.white54;

  void _navigateToCreateGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateGroupScreen(user: widget.user),
      ),
    );
  }

  void _showJoinGroupDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appHeader,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Join via Invite Code',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: textPrimary),
          decoration: InputDecoration(
            labelText: '6-Digit Code',
            labelStyle: const TextStyle(color: textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: appAccent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: appAccent,
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
                style:
                TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
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
          backgroundColor: appAccent.withOpacity(0.2),
          backgroundImage: MemoryImage(bytes),
        );
      } catch (e) {
        debugPrint('Error decoding group avatar: $e');
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: appAccent.withOpacity(0.2),
      child: Text(
        groupName.isNotEmpty ? groupName[0].toUpperCase() : 'G',
        style: TextStyle(
            color: appAccent, fontWeight: FontWeight.bold, fontSize: fontSize),
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
        color: appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread
              ? const Color(0xFF00C897).withOpacity(0.55)
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
                  color: textPrimary,
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
                    ? const Color(0xFF00E676)
                    : (formattedTime.isNotEmpty
                    ? textMuted
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
                    color: isUnread ? Colors.white : textMuted,
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
                    color: const Color(0xFF00C897),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Color(0xFF0F1626),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing:
        const Icon(Icons.arrow_forward_ios, color: textMuted, size: 15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WhatsAppGroupDetailScreen(
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
      backgroundColor: appBackground,
      appBar: AppBar(
        backgroundColor: appHeader,
        elevation: 0,
        title: const Text(
          'Shared Expenses',
          style: TextStyle(
              color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: textMuted),
            onPressed: _showJoinGroupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: textMuted),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Action Buttons Bar
          Container(
            color: appHeader,
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appAccent,
                      foregroundColor: textPrimary,
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
                      side: const BorderSide(color: appAccent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _showJoinGroupDialog,
                    icon: const Icon(Icons.vpn_key_outlined,
                        color: appAccent, size: 20),
                    label: const Text('Join Code',
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Groups Stream List & Empty State
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
                      child: CircularProgressIndicator(color: appAccent));
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
                              color: appAccent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.groups_outlined,
                              size: 72,
                              color: appAccent,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No Active Groups Yet',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Create a group for roomies, trips, or events, or join an existing group with an invite code.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appAccent,
                                foregroundColor: textPrimary,
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
                                    color: appAccent, width: 1.5),
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _showJoinGroupDialog,
                              icon: const Icon(Icons.vpn_key_outlined,
                                  color: appAccent, size: 20),
                              label: const Text(
                                'Join Existing Group',
                                style: TextStyle(
                                  color: textPrimary,
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
// HELPER MODEL FOR CACHED USER PROFILE (NAME + EMAIL + DECODED AVATAR)
// =========================================================================

class _MemberProfile {
  final String displayName;
  final String? email;
  final Uint8List? photoBytes;

  const _MemberProfile({
    required this.displayName,
    this.email,
    this.photoBytes,
  });
}

// =========================================================================
// GROUP CHAT & FINANCIAL DASHBOARD SCREEN (SYSTEM THEMED)
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
}

class _WhatsAppGroupDetailScreenState extends State<WhatsAppGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _expenseTitleController = TextEditingController();
  final TextEditingController _expenseAmountController =
  TextEditingController();

  final Map<String, Future<_MemberProfile>> _profileFutures = {};
  int _lastSeenMessageCount = -1;

  static const Color appBackground = Color(0xFF0F1626);
  static const Color appHeader = Color(0xFF132247);
  static const Color appCard = Color(0xFF1A2642);
  static const Color appAccent = Color(0xFF6C5CE7);
  static const Color appMyBubble = Color(0xFF6C5CE7);
  static const Color appOtherBubble = Color(0xFF1A2642);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Colors.white54;

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
    super.dispose();
  }

  Future<void> _markGroupAsRead() async {
    try {
      await _db.collection('groups').doc(widget.groupId).set({
        'lastReadAt': {
          widget.user.uid: FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error marking group as read: $e');
    }
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
    } catch (e) {
      debugPrint('Error updating lastMessage metadata: $e');
    }
  }

  Uint8List? _decodeBase64Safe(String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    try {
      final cleanBase64 = rawBase64.contains(',')
          ? rawBase64.split(',').last.trim()
          : rawBase64.trim();
      return base64Decode(cleanBase64);
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
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

    if (uid != null && uid.isNotEmpty) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          userData = doc.data();
        }
      } catch (e) {
        debugPrint('Error fetching user profile by uid: $e');
      }
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
        }
      } catch (e) {
        debugPrint('Error fetching user profile by email: $e');
      }
    }

    if (userData != null) {
      final String? dbName = userData['displayName'] as String?;
      final String? dbEmail = userData['email'] as String?;
      final String? dbPhoto = userData['profilePicture'] as String?;
      final String resolvedName = (dbName != null && dbName.trim().isNotEmpty)
          ? dbName.trim()
          : (emailOrFallback != null && emailOrFallback.contains('@')
          ? emailOrFallback.split('@').first
          : (emailOrFallback?.trim().isNotEmpty == true
          ? emailOrFallback!.trim()
          : 'Member'));

      return _MemberProfile(
        displayName: resolvedName,
        email: dbEmail,
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

    return _MemberProfile(displayName: fallbackName, email: emailOrFallback);
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

  Widget _buildDbDisplayNameText({
    String? uid,
    String? emailOrFallback,
    String prefix = '',
    required TextStyle style,
  }) {
    return FutureBuilder<_MemberProfile>(
      future:
      _getCachedMemberProfile(uid: uid, emailOrFallback: emailOrFallback),
      builder: (context, snapshot) {
        final String name = snapshot.data?.displayName ??
            (emailOrFallback != null && !emailOrFallback.contains('@')
                ? emailOrFallback
                : '...');
        return Text(
          '$prefix$name',
          style: style,
        );
      },
    );
  }

  Widget _buildUserChatAvatar({
    String? uid,
    String? emailOrFallback,
    double radius = 16,
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
        final String initial = (profile != null && profile.displayName.isNotEmpty)
            ? profile.displayName[0].toUpperCase()
            : fallbackInitial;

        if (photoBytes != null) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: appAccent.withOpacity(0.25),
            backgroundImage: MemoryImage(photoBytes),
          );
        }

        return CircleAvatar(
          radius: radius,
          backgroundColor: appAccent.withOpacity(0.25),
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: radius * 0.78,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  void _showAddExpenseModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: appHeader,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Group Expense',
              style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _expenseTitleController,
              style: const TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'Expense Description',
                labelStyle: const TextStyle(color: textMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: appAccent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expenseAmountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'Total Amount (\$)',
                labelStyle: const TextStyle(color: textMuted),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(
                    color: textPrimary, fontWeight: FontWeight.bold),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: appAccent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: appAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final title = _expenseTitleController.text.trim();
                  final amount =
                      double.tryParse(_expenseAmountController.text) ?? 0.0;
                  if (title.isEmpty || amount <= 0) return;

                  final String displayName = await _getCurrentUserDisplayName();
                  final String systemSummary =
                      '💵 $displayName added shared expense: "$title" for \$${amount.toStringAsFixed(2)}';

                  await _db
                      .collection('groups')
                      .doc(widget.groupId)
                      .collection('expenses')
                      .add({
                    'title': title,
                    'amount': amount,
                    'paidBy': displayName,
                    'paidById': widget.user.uid,
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
                  _expenseAmountController.clear();
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Share Expense',
                    style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarAvatar(String? liveAvatarBase64, String liveGroupName) {
    final bytes = _decodeBase64Safe(liveAvatarBase64);
    if (bytes != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: appAccent.withOpacity(0.25),
        backgroundImage: MemoryImage(bytes),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: appAccent.withOpacity(0.25),
      child: Text(
        liveGroupName.isNotEmpty ? liveGroupName[0].toUpperCase() : 'G',
        style: const TextStyle(
            color: appAccent, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _openGroupInfoPage(
      String currentGroupName, String? currentAvatarBase64) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhatsAppGroupInfoScreen(
          user: widget.user,
          groupId: widget.groupId,
          initialGroupName: currentGroupName,
          initialAvatarBase64: currentAvatarBase64,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBackground,
      appBar: AppBar(
        backgroundColor: appHeader,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: textPrimary),
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
              onTap: () => _openGroupInfoPage(liveGroupName, liveAvatarBase64),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
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
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            members.isNotEmpty
                                ? '${members.length} ${members.length == 1 ? 'member' : 'members'} • Tap for group info'
                                : 'Tap here for group info',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                            const TextStyle(color: textMuted, fontSize: 11),
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
          indicatorColor: appAccent,
          indicatorWeight: 3,
          labelColor: appAccent,
          unselectedLabelColor: textMuted,
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
          // TAB 1: GROUP CHAT INTERFACE
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
                          child: CircularProgressIndicator(color: appAccent));
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
                          '🔒 Messages and shared expenses are synced live.\nStart the conversation below!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 12),
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
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: appHeader,
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
                                  MediaQuery.of(context).size.width * 0.75),
                              margin: EdgeInsets.only(
                                top: isFirstInSequence ? 6 : 2,
                                bottom: 2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: appMyBubble,
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
                                    color: textPrimary, fontSize: 14.5),
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
                                _buildUserChatAvatar(
                                  uid: senderId,
                                  emailOrFallback: fallbackSender,
                                  radius: 16,
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
                                    color: appOtherBubble,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(
                                          isFirstInSequence ? 4 : 14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: Radius.zero,
                                      bottomRight: const Radius.circular(14),
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
                                          child: _buildDbDisplayNameText(
                                            uid: senderId,
                                            emailOrFallback: fallbackSender,
                                            style: const TextStyle(
                                              color: Colors.cyanAccent,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        msg['text'] ?? '',
                                        style: const TextStyle(
                                            color: textPrimary, fontSize: 14.5),
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
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: appBackground,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: appHeader,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_emotions_outlined,
                                color: textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _msgController,
                                style: const TextStyle(color: textPrimary),
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  hintStyle: TextStyle(color: textMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.attach_file,
                                  color: textMuted),
                              onPressed: _showAddExpenseModal,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: appAccent,
                      child: IconButton(
                        icon: const Icon(Icons.send,
                            color: textPrimary, size: 20),
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
              ),
            ],
          ),

          // TAB 2: FINANCIAL SUMMARY & GROUP TRANSACTION HISTORY
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('groups').doc(widget.groupId).snapshots(),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: appAccent));
              }

              final groupData =
                  groupSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              final double groupBudget =
                  (groupData['budget'] as num?)?.toDouble() ?? 0.0;

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
                        child: CircularProgressIndicator(color: appAccent));
                  }

                  final expenses = expenseSnapshot.data!.docs;

                  double totalSpent = 0.0;
                  for (var doc in expenses) {
                    final data = doc.data() as Map<String, dynamic>;
                    totalSpent += (data['amount'] as num?)?.toDouble() ?? 0.0;
                  }

                  final double remainingBudget = groupBudget - totalSpent;
                  final double progress = groupBudget > 0
                      ? (totalSpent / groupBudget).clamp(0.0, 1.0)
                      : 0.0;
                  final bool isOverBudget =
                      groupBudget > 0 && totalSpent > groupBudget;

                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: appCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text('Group Budget',
                                          style: TextStyle(
                                              color: textMuted, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${groupBudget.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            color: textPrimary,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Total Spent',
                                          style: TextStyle(
                                              color: textMuted, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${totalSpent.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: isOverBudget
                                              ? Colors.redAccent
                                              : Colors.greenAccent,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isOverBudget
                                        ? 'Over Budget'
                                        : 'Remaining Budget',
                                    style: const TextStyle(
                                        color: textMuted, fontSize: 12),
                                  ),
                                  Text(
                                    '\$${remainingBudget.abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: isOverBudget
                                          ? Colors.redAccent
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isOverBudget ? Colors.redAccent : appAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _showAddExpenseModal,
                            icon: const Icon(Icons.add, color: textPrimary),
                            label: const Text('Add Shared Expense',
                                style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'Group Transactions',
                          style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),

                        Expanded(
                          child: expenses.isEmpty
                              ? const Center(
                            child: Text(
                                'No group expenses recorded yet.',
                                style: TextStyle(color: textMuted)),
                          )
                              : ListView.builder(
                            itemCount: expenses.length,
                            itemBuilder: (context, index) {
                              final data = expenses[index].data()
                              as Map<String, dynamic>;
                              final String title =
                                  data['title'] ?? 'Expense';
                              final double amount =
                                  (data['amount'] as num?)?.toDouble() ??
                                      0.0;
                              final String? paidById =
                              data['paidById'] as String?;
                              final String? paidByRaw =
                              data['paidBy'] as String?;
                              final Timestamp? ts =
                              data['timestamp'] as Timestamp?;
                              final String formattedDate = ts != null
                                  ? DateFormat('MMM dd, yyyy • hh:mm a')
                                  .format(ts.toDate())
                                  : 'Just now';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: appCard,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                  Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding:
                                          const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withOpacity(0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.shopping_bag_outlined,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                  color: textPrimary,
                                                  fontWeight:
                                                  FontWeight.bold,
                                                  fontSize: 15),
                                            ),
                                            const SizedBox(height: 4),
                                            _buildDbDisplayNameText(
                                              uid: paidById,
                                              emailOrFallback: paidByRaw,
                                              prefix: 'Paid by: ',
                                              style: const TextStyle(
                                                  color: textMuted,
                                                  fontSize: 12),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              formattedDate,
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '-\$${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
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
  }
}

// =========================================================================
// WHATSAPP-STYLE GROUP INFO / DETAIL SCREEN (ADMIN CONTROLS + ICON PICKER)
// =========================================================================

class WhatsAppGroupInfoScreen extends StatefulWidget {
  final User user;
  final String groupId;
  final String initialGroupName;
  final String? initialAvatarBase64;

  const WhatsAppGroupInfoScreen({
    super.key,
    required this.user,
    required this.groupId,
    required this.initialGroupName,
    this.initialAvatarBase64,
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

  static const Color appBackground = Color(0xFF0F1626);
  static const Color appHeader = Color(0xFF132247);
  static const Color appCard = Color(0xFF1A2642);
  static const Color appAccent = Color(0xFF6C5CE7);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Colors.white54;

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
        final String? dbPhoto = data['profilePicture'] as String?;

        final String name = (dbName != null && dbName.trim().isNotEmpty)
            ? dbName.trim()
            : (dbEmail != null && dbEmail.contains('@')
            ? dbEmail.split('@').first
            : 'Member');

        return _MemberProfile(
          displayName: name,
          email: dbEmail,
          photoBytes: _decodeBase64Safe(dbPhoto),
        );
      }
    } catch (e) {
      debugPrint('Error fetching member $uid: $e');
    }
    return const _MemberProfile(displayName: 'Member');
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
            backgroundColor: Color(0xFF00C897),
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
        backgroundColor: appHeader,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Group Name',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter group name',
            hintStyle: const TextStyle(color: textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: appAccent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: appAccent,
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
                style:
                TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
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

  void _showMemberActionsSheet({
    required String targetUid,
    required String targetName,
    required bool targetIsAdmin,
    required Set<String> currentAdmins,
    required String? createdBy,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: appHeader,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      targetName,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (targetIsAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C897).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFF00C897), width: 0.8),
                        ),
                        child: const Text(
                          'Group Admin',
                          style: TextStyle(
                            color: Color(0xFF00C897),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              if (!targetIsAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined,
                      color: Color(0xFF00C897)),
                  title: const Text(
                    'Make Group Admin',
                    style: TextStyle(
                        color: textPrimary, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Allow this member to change group icon & manage admins',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
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
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _dismissAdminRole(
                        targetUid, targetName, currentAdmins, createdBy);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined,
                    color: Colors.redAccent),
                title: Text(
                  'Remove $targetName',
                  style: const TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeMemberFromGroup(
                      targetUid, targetName, currentAdmins, createdBy);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeaveGroup(Set<String> currentAdmins,
      List<String> members, String? createdBy) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appHeader,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Exit Group?',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to leave this group?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
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
          backgroundColor: appBackground,
          appBar: AppBar(
            backgroundColor: appHeader,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Group Info',
              style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                // --- TOP GROUP PROFILE HEADER ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                  decoration: const BoxDecoration(
                    color: appHeader,
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
                                  color: appAccent.withOpacity(0.75),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: appAccent.withOpacity(0.25),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
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
                                  color: appAccent.withOpacity(0.2),
                                  alignment: Alignment.center,
                                  child: Text(
                                    groupName.isNotEmpty
                                        ? groupName[0].toUpperCase()
                                        : 'G',
                                    style: const TextStyle(
                                      color: appAccent,
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
                                    color: appAccent,
                                    shape: BoxShape.circle,
                                    border:
                                    Border.all(color: appHeader, width: 2),
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
                      if (isCurrentUserAdmin) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _isUpdatingIcon ? null : _changeGroupIcon,
                          child: const Text(
                            'Tap icon to change group photo',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              groupName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: textPrimary,
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
                        'Group • ${members.length} ${members.length == 1 ? 'member' : 'members'}',
                        style: const TextStyle(color: textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // --- INVITE CODE & BUDGET DETAILS CARD ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: appCard,
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
                                    color: appAccent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.vpn_key_outlined,
                                      color: appAccent, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Group Invite Code',
                                      style: TextStyle(
                                          color: textMuted, fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      inviteCode.isNotEmpty
                                          ? inviteCode
                                          : '------',
                                      style: const TextStyle(
                                        color: textPrimary,
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
                                tooltip: 'Copy invite code',
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: inviteCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Invite code copied to clipboard!')),
                                  );
                                },
                              ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 22),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                const Color(0xFF00C897).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Color(0xFF00C897),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Group Budget',
                                  style:
                                  TextStyle(color: textMuted, fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '\$${budget.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // --- MEMBERS & ADMINS LIST CARD ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: appCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${members.length} ${members.length == 1 ? 'Participant' : 'Participants'}',
                                style: const TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isCurrentUserAdmin)
                                const Text(
                                  'Tap a member to manage admin',
                                  style: TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
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
                                  onTap: (isCurrentUserAdmin && !isMe)
                                      ? () => _showMemberActionsSheet(
                                    targetUid: memberUid,
                                    targetName: displayName,
                                    targetIsAdmin: isMemberAdmin,
                                    currentAdmins: adminSet,
                                    createdBy: createdBy,
                                  )
                                      : null,
                                  leading: photoBytes != null
                                      ? CircleAvatar(
                                    radius: 21,
                                    backgroundColor:
                                    appAccent.withOpacity(0.25),
                                    backgroundImage:
                                    MemoryImage(photoBytes),
                                  )
                                      : CircleAvatar(
                                    radius: 21,
                                    backgroundColor:
                                    appAccent.withOpacity(0.25),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          isMe
                                              ? '$displayName (You)'
                                              : displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: textPrimary,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: email != null && email.isNotEmpty
                                      ? Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textMuted,
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
                                            color: const Color(0xFF00C897)
                                                .withOpacity(0.15),
                                            borderRadius:
                                            BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFF00C897)
                                                  .withOpacity(0.6),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Text(
                                            'Group Admin',
                                            style: TextStyle(
                                              color: Color(0xFF00C897),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (isCurrentUserAdmin && !isMe) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.more_vert,
                                          color: textMuted,
                                          size: 18,
                                        ),
                                      ],
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

                // --- EXIT GROUP CARD ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: appCard,
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