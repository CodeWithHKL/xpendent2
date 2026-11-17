import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/home_screen.dart';
import 'services/notification_service.dart';
import 'splash_screen.dart';

// Top-level background handler for mobile FCM messages when app is terminated/backgrounded
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // If the push notification includes a notification payload, show it locally
  final RemoteNotification? notification = message.notification;
  if (notification != null) {
    final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

    // Initialize high importance channel for background display
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'group_messages_channel',
      'Group Messages',
      importance: Importance.max,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await plugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'group_messages_channel',
          'Group Messages',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

// Top-level background worker that polls Firestore on Android when closed
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return true;

      final prefs = await SharedPreferences.getInstance();
      final expenseAlertsEnabled =
          prefs.getBool('expense_notifications_enabled') ?? true;

      final groupsSnap = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: uid)
          .get();

      final plugin = FlutterLocalNotificationsPlugin();

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'group_messages_channel',
        'Group Messages',
        importance: Importance.max,
      );

      await plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      for (final doc in groupsSnap.docs) {
        final data = doc.data();
        final Timestamp? ts = data['lastMessageTime'] as Timestamp?;
        final String? senderId = data['lastMessageSenderId'] as String?;
        if (ts == null || senderId == null || senderId == uid) continue;

        final int msgMillis = ts.millisecondsSinceEpoch;
        final String prefKey = 'bg_last_notified_${doc.id}';
        final int lastSeen = prefs.getInt(prefKey) ?? 0;

        if (lastSeen == 0) {
          await prefs.setInt(prefKey, msgMillis);
          continue;
        }

        if (msgMillis <= lastSeen) continue;
        await prefs.setInt(prefKey, msgMillis);

        final String groupName = (data['name'] as String?) ?? 'Group Expense';
        final String senderName =
            (data['lastMessageSender'] as String?) ?? 'Member';
        final String text = (data['lastMessage'] as String?) ?? '';
        if (text.trim().isEmpty) continue;

        final bool isExpense =
            text.startsWith('💵') || text.contains('added shared expense:');
        if (isExpense && !expenseAlertsEnabled) continue;

        await plugin.show(
          doc.id.hashCode ^ msgMillis.hashCode,
          isExpense ? 'New Group Expense • $groupName' : groupName,
          isExpense ? text : '$senderName: $text',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'group_messages_channel',
              'Group Messages',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    } catch (_) {}
    return true;
  });
}

Future<void> _setupPushNotifications() async {
  try {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ensure foreground presentation options allow banners
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': token}, SetOptions(merge: true));
        }
      } catch (_) {}
    });

    messaging.onTokenRefresh.listen((newToken) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'fcmToken': newToken}, SetOptions(merge: true));
      }
    });
  } catch (e) {
    debugPrint('Push notification setup skipped: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Run mobile-only background services only on Android/iOS (never on Chrome Web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _setupPushNotifications();

    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'xpendent-group-sync',
      'checkGroupUpdates',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );

    await NotificationService().init();
  }

  runApp(const XpendentApp());
}

class XpendentApp extends StatelessWidget {
  const XpendentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xpendent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(
        nextScreen: _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1626),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return HomeScreen(user: snapshot.data!);
        }
        return const LoginScreen();
      },
    );
  }
}