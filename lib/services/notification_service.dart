import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/goal_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _budgetAlertsKey = 'pref_budget_alerts';
  static const String _goalRemindersKey = 'pref_goal_reminders';
  static const String _expenseNotifsKey = 'pref_expense_notifications';

  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Tracks sent alerts in-session so StreamBuilder rebuilds don't spam
  final Set<String> _sentBudgetAlerts = <String>{};

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

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

    await _notifications.initialize(initSettings);

    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // --- PREFERENCE GETTERS & SETTERS ---

  Future<bool> isBudgetAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_budgetAlertsKey) ?? true;
  }

  Future<void> setBudgetAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_budgetAlertsKey, enabled);
    if (!enabled) {
      _sentBudgetAlerts.clear();
    }
  }

  Future<bool> isGoalRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_goalRemindersKey) ?? true;
  }

  Future<void> setGoalRemindersEnabled(
      bool enabled, {
        List<GoalModel> activeGoals = const [],
      }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_goalRemindersKey, enabled);

    if (!enabled) {
      await cancelAllScheduledNotifications();
    } else {
      for (final goal in activeGoals) {
        if (!goal.isCompleted) {
          await scheduleGoalReminders(goal);
        }
      }
    }
  }

  Future<bool> isExpenseNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_expenseNotifsKey) ?? true;
  }

  Future<void> setExpenseNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expenseNotifsKey, enabled);
  }

  // --- GOAL REMINDERS ---

  int _notifId(String goalId, int offsetTag) {
    return (goalId.hashCode.abs() % 100000) * 10 + offsetTag;
  }

  Future<void> scheduleGoalReminders(GoalModel goal) async {
    await init();
    await cancelGoalReminders(goal.id);

    // Respect user's Goal Reminders toggle
    if (!await isGoalRemindersEnabled()) return;
    if (goal.isCompleted) return;

    final now = DateTime.now();
    final reminders = <int, String>{
      3: 'Only 3 days left to reach your "${goal.title}" goal!',
      1: 'Reminder: "${goal.title}" is due tomorrow!',
      0: 'Today is the target date for "${goal.title}"!',
    };

    for (final entry in reminders.entries) {
      final daysBefore = entry.key;
      final message = entry.value;

      final targetDay = goal.targetDate.subtract(Duration(days: daysBefore));
      final scheduledDateTime = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        9,
        0,
      );

      if (scheduledDateTime.isAfter(now)) {
        await _notifications.zonedSchedule(
          _notifId(goal.id, daysBefore),
          'Goal Deadline Approaching',
          message,
          tz.TZDateTime.from(scheduledDateTime, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'goal_reminders_channel',
              'Goal Reminders',
              channelDescription: 'Notifications when savings goals are due soon',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> cancelGoalReminders(String goalId) async {
    await init();
    await _notifications.cancel(_notifId(goalId, 3));
    await _notifications.cancel(_notifId(goalId, 1));
    await _notifications.cancel(_notifId(goalId, 0));
  }

  Future<void> cancelAllScheduledNotifications() async {
    await init();
    await _notifications.cancelAll();
  }

  // --- BUDGET ALERTS ---

  Future<void> _showBudgetNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _notifications.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_alerts_channel',
          'Budget Alerts',
          channelDescription:
          'Notifications when budgets are running low or exceeded',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> checkAndNotifyBudgetAlerts({
    required int year,
    required int month,
    required String currencySymbol,
    required double totalBudget,
    required double totalSpent,
    required Map<String, double> budgets,
    required Map<String, double> categorySpent,
  }) async {
    // Respect user's Budget Alerts toggle
    if (!await isBudgetAlertsEnabled()) return;

    if (totalBudget > 0.0) {
      final double overallRatio = totalSpent / totalBudget;
      if (overallRatio > 1.0) {
        final String key = '${year}_${month}_overall_over';
        if (_sentBudgetAlerts.add(key)) {
          final double overBy = totalSpent - totalBudget;
          await _showBudgetNotification(
            id: key.hashCode.abs() % 200000,
            title: 'Total Budget Exceeded!',
            body:
            'You exceeded your monthly budget by $currencySymbol${overBy.toStringAsFixed(2)}.',
          );
        }
      } else if (overallRatio >= 0.8) {
        final String key = '${year}_${month}_overall_low';
        if (_sentBudgetAlerts.add(key)) {
          final double left = totalBudget - totalSpent;
          await _showBudgetNotification(
            id: key.hashCode.abs() % 200000,
            title: 'Total Budget Running Low',
            body:
            '${(overallRatio * 100).toStringAsFixed(0)}% of your monthly budget is used ($currencySymbol${left.toStringAsFixed(2)} left).',
          );
        }
      }
    }

    for (final entry in budgets.entries) {
      final String category = entry.key;
      final double allocated = entry.value;
      if (allocated <= 0.0) continue;

      final double spent = categorySpent[category] ?? 0.0;
      final double ratio = spent / allocated;

      if (ratio > 1.0) {
        final String key = '${year}_${month}_${category}_over';
        if (_sentBudgetAlerts.add(key)) {
          await _showBudgetNotification(
            id: key.hashCode.abs() % 200000,
            title: '$category Budget Exceeded!',
            body:
            'You spent $currencySymbol${spent.toStringAsFixed(2)} out of $currencySymbol${allocated.toStringAsFixed(2)} for $category.',
          );
        }
      } else if (ratio >= 0.8) {
        final String key = '${year}_${month}_${category}_low';
        if (_sentBudgetAlerts.add(key)) {
          final double left = allocated - spent;
          await _showBudgetNotification(
            id: key.hashCode.abs() % 200000,
            title: '$category Budget Running Low',
            body:
            '${(ratio * 100).toStringAsFixed(0)}% used for $category ($currencySymbol${left.toStringAsFixed(2)} remaining).',
          );
        }
      }
    }
  }
}