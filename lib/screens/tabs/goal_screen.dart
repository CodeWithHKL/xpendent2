import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/goal_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

/// Formats raw digit input into standard 2-decimal currency
class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat formatter = NumberFormat('#,##0.00');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '0.00');
    }

    double doubleValue = double.parse(digitsOnly) / 100.0;
    String newText = formatter.format(doubleValue);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

enum AnimationType { confetti, fireworks, balloons }

class GoalScreen extends StatefulWidget {
  final User user;
  const GoalScreen({super.key, required this.user});

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();
  bool _showCompletedTab = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00');

  // Master Full-Screen Animation Controller
  late AnimationController _celebrationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _bannerSlideAnimation;

  final List<_VisualParticle> _particles = [];
  final Random _random = Random();
  String _completedGoalTitle = '';
  AnimationType _selectedAnimation = AnimationType.confetti;

  @override
  void initState() {
    super.initState();
    _notificationService.init();

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..addListener(() {
      setState(() {});
    });

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_celebrationController);

    _bannerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: const Interval(0.0, 0.25, curve: Curves.elasticOut),
      ),
    );
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  void _syncGoalNotifications(List<GoalModel> allGoals) {
    for (final goal in allGoals) {
      if (goal.isCompleted) {
        _notificationService.cancelGoalReminders(goal.id);
      } else {
        _notificationService.scheduleGoalReminders(goal);
      }
    }
  }

  void _triggerRandomFullScreenSuccessAnimation(GoalModel goal) {
    setState(() {
      _completedGoalTitle = goal.title;
      _selectedAnimation =
      AnimationType.values[_random.nextInt(AnimationType.values.length)];
    });

    _particles.clear();
    final colors = [
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.purpleAccent,
      Colors.pinkAccent,
      Colors.orangeAccent,
    ];

    if (_selectedAnimation == AnimationType.confetti) {
      for (int i = 0; i < 80; i++) {
        _particles.add(
          _VisualParticle(
            x: _random.nextDouble(),
            y: _random.nextDouble() * 0.4 + 0.1,
            color: colors[_random.nextInt(colors.length)],
            size: _random.nextDouble() * 10 + 6,
            speedY: _random.nextDouble() * 1.8 + 0.8,
            speedX: (_random.nextDouble() - 0.5) * 2.0,
            rotation: _random.nextDouble() * 2 * pi,
          ),
        );
      }
    } else if (_selectedAnimation == AnimationType.fireworks) {
      for (int i = 0; i < 70; i++) {
        double angle = _random.nextDouble() * 2 * pi;
        double speed = _random.nextDouble() * 2.5 + 1.0;
        _particles.add(
          _VisualParticle(
            x: 0.5,
            y: 0.4,
            color: colors[_random.nextInt(colors.length)],
            size: _random.nextDouble() * 8 + 4,
            speedX: cos(angle) * speed,
            speedY: sin(angle) * speed,
            rotation: 0.0,
          ),
        );
      }
    } else {
      for (int i = 0; i < 25; i++) {
        _particles.add(
          _VisualParticle(
            x: _random.nextDouble(),
            y: 1.1 + _random.nextDouble() * 0.3,
            color: colors[_random.nextInt(colors.length)],
            size: _random.nextDouble() * 20 + 24,
            speedY: -(_random.nextDouble() * 1.2 + 0.8),
            speedX: (_random.nextDouble() - 0.5) * 0.5,
            rotation: 0.0,
          ),
        );
      }
    }

    _celebrationController.forward(from: 0.0);
  }

  void _handleDeleteGoal(GoalModel goal) {
    if (goal.isCompleted) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF132247),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Delete Completed Goal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Are you sure you want to delete "${goal.title}"? This completed achievement will be permanently removed.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _notificationService.cancelGoalReminders(goal.id);
                  await _firestoreService.deleteGoal(widget.user.uid, goal.id);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    } else {
      _notificationService.cancelGoalReminders(goal.id);
      _firestoreService.deleteGoal(widget.user.uid, goal.id);
    }
  }

  double _parseFormattedAmount(String text) {
    if (text.isEmpty) return 0.0;
    String cleanText = text.replaceAll(',', '').trim();
    return double.tryParse(cleanText) ?? 0.0;
  }

  void _showAddGoalBottomSheet(String userCurrencyCode) {
    final titleController = TextEditingController();
    final targetAmountController = TextEditingController();
    final initialAmountController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 30));
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131D33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add New Goal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Goal Name',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E2D4A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: targetAmountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Target Amount ($userCurrencyCode)',
                      hintText: '0.00',
                      hintStyle: const TextStyle(color: Colors.white38),
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E2D4A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: initialAmountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Currently Saved ($userCurrencyCode)',
                      hintText: '0.00',
                      hintStyle: const TextStyle(color: Colors.white38),
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E2D4A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Target Date',
                            style:
                            TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd MMMM yyyy').format(selectedDate),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1D61E7),
                        ),
                        onPressed: () async {
                          final isDark =
                              MediaQuery.of(context).platformBrightness ==
                                  Brightness.dark;

                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2035),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: isDark
                                      ? const ColorScheme.dark(
                                    primary: Color(0xFF1D61E7),
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF132247),
                                    onSurface: Colors.white,
                                  )
                                      : const ColorScheme.light(
                                    primary: Color(0xFF1D61E7),
                                    onPrimary: Colors.white,
                                    surface: Colors.white,
                                    onSurface: Colors.black87,
                                  ),
                                  dialogBackgroundColor: isDark
                                      ? const Color(0xFF132247)
                                      : Colors.white,
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setModalState(() => selectedDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Pick Date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D61E7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                        final title = titleController.text.trim();
                        final target = _parseFormattedAmount(
                            targetAmountController.text);
                        final saved = _parseFormattedAmount(
                            initialAmountController.text);

                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                Text('Please enter a goal name')),
                          );
                          return;
                        }

                        if (target <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please enter a valid target amount (> 0.00)')),
                          );
                          return;
                        }

                        setModalState(() => isSubmitting = true);

                        try {
                          final newGoal = GoalModel(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            title: title,
                            targetAmount: target.toInt(),
                            currentAmount: saved.toInt(),
                            targetDate: selectedDate,
                          );

                          await _firestoreService.addGoal(
                              widget.user.uid, newGoal);

                          if (!newGoal.isCompleted) {
                            await _notificationService
                                .scheduleGoalReminders(newGoal);
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            if (newGoal.isCompleted) {
                              _triggerRandomFullScreenSuccessAnimation(
                                  newGoal);
                            }
                          }
                        } catch (e) {
                          setModalState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                  Text('Failed to save goal: $e')),
                            );
                          }
                        }
                      },
                      child: isSubmitting
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text(
                        'Create Goal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddProgressDialog(GoalModel goal) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF132247),
          title: Text(
            'Add Progress for ${goal.title}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              CurrencyInputFormatter(),
            ],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E2D4A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
              const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D61E7)),
              onPressed: () async {
                final addVal =
                _parseFormattedAmount(amountController.text).toInt();
                if (addVal > 0) {
                  int updatedAmount = (goal.currentAmount + addVal)
                      .clamp(0, goal.targetAmount);

                  await _firestoreService.updateGoalProgress(
                    widget.user.uid,
                    goal.id,
                    updatedAmount,
                  );

                  if (mounted) Navigator.pop(context);

                  if (updatedAmount >= goal.targetAmount) {
                    await _notificationService.cancelGoalReminders(goal.id);
                    final updatedGoal = GoalModel(
                      id: goal.id,
                      title: goal.title,
                      targetAmount: goal.targetAmount,
                      currentAmount: updatedAmount,
                      targetDate: goal.targetDate,
                    );
                    _triggerRandomFullScreenSuccessAnimation(updatedGoal);
                  }
                }
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCelebrationBadge() {
    IconData icon;
    Color glowColor;
    String headingText;

    switch (_selectedAnimation) {
      case AnimationType.fireworks:
        icon = Icons.star_rounded;
        glowColor = Colors.cyanAccent;
        headingText = 'AMAZING ACHIEVEMENT!';
        break;
      case AnimationType.balloons:
        icon = Icons.celebration_rounded;
        glowColor = Colors.pinkAccent;
        headingText = 'PARTY TIME!';
        break;
      case AnimationType.confetti:
      default:
        icon = Icons.emoji_events_rounded;
        glowColor = Colors.amberAccent;
        headingText = 'GOAL COMPLETED!';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: glowColor.withOpacity(0.2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Icon(
            icon,
            color: glowColor,
            size: 80,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          headingText,
          style: TextStyle(
            color: glowColor,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'You saved for "$_completedGoalTitle"',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.getUserProfile(widget.user.uid),
      builder: (context, profileSnapshot) {
        String currencyCode = 'MYR';

        if (profileSnapshot.hasData && profileSnapshot.data!.data() != null) {
          final profileData =
          profileSnapshot.data!.data() as Map<String, dynamic>;
          if (profileData['currencyCode'] != null &&
              (profileData['currencyCode'] as String).isNotEmpty) {
            currencyCode = profileData['currencyCode'] as String;
          } else if (profileData['currencySymbol'] != null &&
              (profileData['currencySymbol'] as String).isNotEmpty) {
            currencyCode = profileData['currencySymbol'] as String;
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F1626),
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                StreamBuilder<List<GoalModel>>(
                  stream: _firestoreService.getGoals(widget.user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading goals: ${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      );
                    }

                    final allGoals = snapshot.data ?? [];
                    _syncGoalNotifications(allGoals);

                    final activeGoals =
                    allGoals.where((g) => !g.isCompleted).toList();
                    final completedGoals =
                    allGoals.where((g) => g.isCompleted).toList();
                    final displayGoals =
                    _showCompletedTab ? completedGoals : activeGoals;

                    return Column(
                      children: [
                        // --- HOMESCREEN WALLPAPER TOP HEADER CONTAINER ---
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(24)),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.asset(
                                  'assets/wallpaper10.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF132247),
                                            Color(0xFF0C1327)
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.only(
                                    top: 10, left: 16, right: 16, bottom: 16),
                                color: Colors.black.withOpacity(0.20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: Colors.white10,
                                          child: Icon(Icons.person_outline,
                                              color: Colors.white, size: 20),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'My Goals',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                            _showCompletedTab = false),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              curve: Curves.easeInOut,
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: !_showCompletedTab
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFF1E2D4A)
                                                    .withOpacity(0.85),
                                                borderRadius:
                                                BorderRadius.circular(18),
                                                border: Border.all(
                                                  color: !_showCompletedTab
                                                      ? Colors.blue.shade400
                                                      : Colors.transparent,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  const Row(
                                                    children: [
                                                      Icon(Icons.track_changes,
                                                          color: Colors.white70,
                                                          size: 18),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Active Goals',
                                                        style: TextStyle(
                                                            color:
                                                            Colors.white70,
                                                            fontSize: 12),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    '${activeGoals.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 26,
                                                      fontWeight:
                                                      FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(
                                                    () => _showCompletedTab = true),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              curve: Curves.easeInOut,
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: _showCompletedTab
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFF1E2D4A)
                                                    .withOpacity(0.85),
                                                borderRadius:
                                                BorderRadius.circular(18),
                                                border: Border.all(
                                                  color: _showCompletedTab
                                                      ? Colors.blue.shade400
                                                      : Colors.transparent,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  const Row(
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .assignment_turned_in_outlined,
                                                          color: Colors.white70,
                                                          size: 18),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Completed',
                                                        style: TextStyle(
                                                            color:
                                                            Colors.white70,
                                                            fontSize: 12),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    '${completedGoals.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 26,
                                                      fontWeight:
                                                      FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeInOutCubic,
                            switchOutCurve: Curves.easeInOutCubic,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              final isCompletedWidget =
                                  child.key == const ValueKey<bool>(true);

                              final double beginX =
                              isCompletedWidget ? 1.0 : -1.0;

                              final slideAnimation = Tween<Offset>(
                                begin: Offset(beginX, 0.0),
                                end: Offset.zero,
                              ).animate(animation);

                              return SlideTransition(
                                position: slideAnimation,
                                child: child,
                              );
                            },
                            child: Container(
                              key: ValueKey<bool>(_showCompletedTab),
                              color: _showCompletedTab
                                  ? const Color(0xFF112233)
                                  : const Color(0xFF0F1626),
                              child: displayGoals.isEmpty
                                  ? Center(
                                child: Text(
                                  _showCompletedTab
                                      ? 'No completed goals yet'
                                      : 'No active goals',
                                  style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 14),
                                ),
                              )
                                  : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: displayGoals.length,
                                itemBuilder: (context, index) {
                                  final goal = displayGoals[index];
                                  final double progressPercent =
                                  goal.targetAmount > 0
                                      ? (goal.currentAmount /
                                      goal.targetAmount)
                                      .clamp(0.0, 1.0)
                                      : 0.0;
                                  final int percentInt =
                                  (progressPercent * 100).toInt();
                                  final bool isDueSoon =
                                      !goal.isCompleted &&
                                          goal.daysRemaining <= 3;

                                  return Container(
                                    margin:
                                    const EdgeInsets.only(bottom: 14),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A2642),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                      border: goal.isCompleted
                                          ? Border.all(
                                          color: Colors.greenAccent
                                              .withOpacity(0.4),
                                          width: 1.5)
                                          : (isDueSoon
                                          ? Border.all(
                                          color: Colors
                                              .amberAccent
                                              .withOpacity(0.6),
                                          width: 1.5)
                                          : null),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              goal.isCompleted
                                                  ? Icons
                                                  .emoji_events_rounded
                                                  : Icons
                                                  .savings_outlined,
                                              color: goal.isCompleted
                                                  ? Colors.amberAccent
                                                  : (isDueSoon
                                                  ? Colors.amberAccent
                                                  : Colors.white),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                goal.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight:
                                                  FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (isDueSoon)
                                              Container(
                                                margin:
                                                const EdgeInsets.only(
                                                    right: 6),
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                  BorderRadius
                                                      .circular(8),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                  MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .notifications_active,
                                                      color: Colors
                                                          .amberAccent,
                                                      size: 12,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Due Soon',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .amberAccent,
                                                        fontSize: 10,
                                                        fontWeight:
                                                        FontWeight
                                                            .bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.white38,
                                                  size: 20),
                                              onPressed: () =>
                                                  _handleDeleteGoal(goal),
                                            ),
                                          ],
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 32),
                                          child: goal.isCompleted
                                              ? Container(
                                            padding:
                                            const EdgeInsets
                                                .symmetric(
                                                horizontal: 8,
                                                vertical: 2),
                                            decoration:
                                            BoxDecoration(
                                              color: Colors
                                                  .greenAccent
                                                  .withOpacity(0.2),
                                              borderRadius:
                                              BorderRadius
                                                  .circular(8),
                                            ),
                                            child: const Text(
                                              'Goal Reached!',
                                              style: TextStyle(
                                                color: Colors
                                                    .greenAccent,
                                                fontSize: 11,
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                            ),
                                          )
                                              : Text(
                                            '${goal.daysRemaining > 0 ? goal.daysRemaining : 0} days remaining',
                                            style: TextStyle(
                                              color: isDueSoon
                                                  ? Colors
                                                  .amberAccent
                                                  : Colors.white38,
                                              fontSize: 12,
                                              fontWeight: isDueSoon
                                                  ? FontWeight.w600
                                                  : FontWeight
                                                  .normal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                          children: [
                                            Text(
                                              '$currencyCode ${_currencyFormat.format(goal.currentAmount)} of $currencyCode ${_currencyFormat.format(goal.targetAmount)}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              '$percentInt%',
                                              style: TextStyle(
                                                color: goal.isCompleted
                                                    ? Colors.greenAccent
                                                    : Colors.cyanAccent,
                                                fontSize: 12,
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius:
                                          BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: progressPercent,
                                            backgroundColor:
                                            Colors.white10,
                                            color: goal.isCompleted
                                                ? Colors.greenAccent
                                                : Colors.cyanAccent,
                                            minHeight: 6,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        if (!goal.isCompleted)
                                          SizedBox(
                                            width: double.infinity,
                                            height: 38,
                                            child: ElevatedButton(
                                              style: ElevatedButton
                                                  .styleFrom(
                                                backgroundColor:
                                                const Color(
                                                    0xFF2E3E6E),
                                                elevation: 0,
                                                shape:
                                                RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius
                                                      .circular(12),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _showAddProgressDialog(
                                                      goal),
                                              child: const Text(
                                                'Add Progress',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight:
                                                  FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // RANDOM FULL SCREEN CELEBRATION OVERLAY
                if (_celebrationController.isAnimating)
                  IgnorePointer(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black.withOpacity(0.70),
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: Size.infinite,
                              painter: _VisualParticlePainter(
                                particles: _particles,
                                progress: _celebrationController.value,
                                type: _selectedAnimation,
                              ),
                            ),
                            Center(
                              child: _buildCelebrationBadge(),
                            ),
                            Positioned(
                              top: 50,
                              left: 20,
                              right: 20,
                              child: SlideTransition(
                                position: _bannerSlideAnimation,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF132247),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.greenAccent, width: 1.5),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          color: Colors.greenAccent, size: 22),
                                      SizedBox(width: 10),
                                      Text(
                                        'Great job staying on track!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF6C5CE7),
            onPressed: () => _showAddGoalBottomSheet(currencyCode),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Add new goal',
              style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}

class _VisualParticle {
  double x;
  double y;
  final Color color;
  final double size;
  final double speedY;
  final double speedX;
  final double rotation;

  _VisualParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.size,
    required this.speedY,
    required this.speedX,
    required this.rotation,
  });
}

class _VisualParticlePainter extends CustomPainter {
  final List<_VisualParticle> particles;
  final double progress;
  final AnimationType type;

  _VisualParticlePainter({
    required this.particles,
    required this.progress,
    required this.type,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity((1.0 - progress).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      if (type == AnimationType.balloons) {
        double currentX =
            (particle.x + particle.speedX * progress) * size.width;
        double currentY =
            (particle.y + particle.speedY * progress) * size.height;

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(currentX, currentY),
            width: particle.size * 0.8,
            height: particle.size,
          ),
          paint,
        );
      } else if (type == AnimationType.fireworks) {
        double currentX =
            (particle.x + particle.speedX * progress * 0.5) * size.width;
        double currentY =
            (particle.y + particle.speedY * progress * 0.5) * size.height;

        canvas.drawCircle(
            Offset(currentX, currentY), particle.size * 0.5, paint);
      } else {
        double currentX =
            (particle.x + particle.speedX * progress * 0.6) * size.width;
        double currentY =
            (particle.y + particle.speedY * progress * 0.9) * size.height;

        canvas.save();
        canvas.translate(currentX, currentY);
        canvas.rotate(particle.rotation + progress * 6);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size * 0.6,
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VisualParticlePainter oldDelegate) => true;
}