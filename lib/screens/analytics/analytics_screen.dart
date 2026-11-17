import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';

class AnalyticsScreen extends StatefulWidget {
  final User user;
  final int? initialMonth;
  final int? initialYear;

  const AnalyticsScreen({
    super.key,
    required this.user,
    this.initialMonth,
    this.initialYear,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  late int _selectedMonth;
  late int _selectedYear;

  final ScrollController _monthScrollController = ScrollController();
  final List<GlobalKey> _monthKeys = List.generate(12, (_) => GlobalKey());

  // Touch tracking for chart interactivity
  double? _touchedX;

  // Cached data for smooth local transitions
  List<TransactionModel> _allTransactions = [];
  String _currencySymbol = 'RM';
  bool _isLoading = true;

  final List<String> _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth ?? DateTime.now().month;
    _selectedYear = widget.initialYear ?? DateTime.now().year;

    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCenter(_selectedMonth - 1, animate: false);
    });
  }

  Future<void> _loadData() async {
    try {
      final profileFuture = _firestoreService.getUserProfile(widget.user.uid).first;
      final txFuture = _firestoreService.getTransactions(widget.user.uid).first;

      final results = await Future.wait<dynamic>([profileFuture, txFuture]);

      final profileSnapshot = results[0] as DocumentSnapshot;
      if (profileSnapshot.exists && profileSnapshot.data() != null) {
        final profileData = profileSnapshot.data() as Map<String, dynamic>;
        if (profileData['currencySymbol'] != null &&
            (profileData['currencySymbol'] as String).isNotEmpty) {
          _currencySymbol = profileData['currencySymbol'] as String;
        } else if (profileData['currencyCode'] != null) {
          _currencySymbol = profileData['currencyCode'] as String;
        }
      }

      _allTransactions = results[1] as List<TransactionModel>;
    } catch (e) {
      // Handle error silently
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCenter(_selectedMonth - 1, animate: false);
        });
      }
    }
  }

  @override
  void dispose() {
    _monthScrollController.dispose();
    super.dispose();
  }

  void _scrollToCenter(int index, {bool animate = true}) {
    if (index < 0 || index >= _monthKeys.length) return;

    final context = _monthKeys[index].currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final position = box.localToGlobal(Offset.zero, ancestor: this.context.findRenderObject());
        final itemWidth = box.size.width;
        final screenWidth = MediaQuery.of(this.context).size.width;

        final targetOffset = _monthScrollController.offset + position.dx - (screenWidth / 2) + (itemWidth / 2);

        if (animate) {
          _monthScrollController.animateTo(
            targetOffset.clamp(0.0, _monthScrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else {
          _monthScrollController.jumpTo(
            targetOffset.clamp(0.0, _monthScrollController.position.maxScrollExtent),
          );
        }
      }
    }
  }

  void _showYearPicker() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Select Year',
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              height: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF132247),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Select Year',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFF6C5CE7),
                          onPrimary: Colors.white,
                          surface: Color(0xFF132247),
                          onSurface: Colors.white,
                        ),
                      ),
                      child: YearPicker(
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        selectedDate: DateTime(_selectedYear),
                        onChanged: (DateTime dateTime) {
                          setState(() {
                            _selectedYear = dateTime.year;
                            _touchedX = null;
                          });
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToCenter(_selectedMonth - 1);
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1626),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    double totalIncome = 0;
    double totalExpense = 0;
    for (var tx in _allTransactions) {
      if (tx.type == 'income') {
        totalIncome += tx.amount;
      } else {
        totalExpense += tx.amount;
      }
    }
    double overallBalance = totalIncome - totalExpense;

    final monthTransactions = _allTransactions.where((tx) {
      return tx.date.year == _selectedYear && tx.date.month == _selectedMonth;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    double periodIncome = 0;
    double periodExpense = 0;
    Map<String, double> incomeCategories = {};
    Map<String, double> expenseCategories = {};

    for (var tx in monthTransactions) {
      if (tx.type == 'income') {
        periodIncome += tx.amount;
        incomeCategories[tx.category] =
            (incomeCategories[tx.category] ?? 0) + tx.amount;
      } else {
        periodExpense += tx.amount;
        expenseCategories[tx.category] =
            (expenseCategories[tx.category] ?? 0) + tx.amount;
      }
    }

    double periodBalance = periodIncome - periodExpense;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1626),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER ROW WITH YEAR SELECTOR ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A2642),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Analytics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _showYearPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2D4A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$_selectedYear',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- BALANCE & PERIOD BALANCE SUMMARY ---
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2D4A).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Balance',
                                style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              '$_currencySymbol${overallBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C3A42),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Period balance',
                                style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              '${periodBalance >= 0 ? '+' : '-'}$_currencySymbol${periodBalance.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                color: periodBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    'Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white12),

                // --- SCROLLABLE MONTH SELECTOR HORIZONTAL BAR ---
                SizedBox(
                  height: 42,
                  child: SingleChildScrollView(
                    controller: _monthScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        SizedBox(width: MediaQuery.of(context).size.width / 2 - 45),
                        ...List.generate(12, (index) {
                          final int monthNum = index + 1;
                          final bool isSelected = monthNum == _selectedMonth;
                          final String yearSuffix = _selectedYear.toString().substring(2);
                          final String label = '${_months[index]} $yearSuffix';

                          return GestureDetector(
                            key: _monthKeys[index],
                            onTap: () {
                              setState(() {
                                _selectedMonth = monthNum;
                                _touchedX = null;
                              });
                              _scrollToCenter(index);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF2E3E6E) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected
                                    ? Border.all(color: Colors.blueAccent.withOpacity(0.4))
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white54,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        SizedBox(width: MediaQuery.of(context).size.width / 2 - 45),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // --- CONTENT CONTAINER ---
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- SMOOTHLY MORPHING ANIMATED CHART ---
                    GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _touchedX = details.localPosition.dx;
                        });
                      },
                      onPanDown: (details) {
                        setState(() {
                          _touchedX = details.localPosition.dx;
                        });
                      },
                      onPanEnd: (_) {
                        setState(() {
                          _touchedX = null;
                        });
                      },
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: SmoothAnimatedChart(
                          transactions: monthTransactions,
                          selectedMonth: _selectedMonth,
                          selectedYear: _selectedYear,
                          touchedX: _touchedX,
                          currencySymbol: _currencySymbol,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- SMOOTH TRANSITION FOR INCOME & EXPENSE SECTIONS BELOW GRAPH ---
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.04),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>('$_selectedYear-$_selectedMonth'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- INCOME SECTION ---
                          const Row(
                            children: [
                              Icon(Icons.archive_outlined, color: Colors.greenAccent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Income',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '+$_currencySymbol${periodIncome.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (incomeCategories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Text(
                                'No income recorded for this period',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            )
                          else
                            Column(
                              children: incomeCategories.entries.map((entry) {
                                final double percentage = periodIncome > 0
                                    ? (entry.value / periodIncome) * 100
                                    : 0;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A2642),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${percentage.toStringAsFixed(0)}%  ($_currencySymbol${entry.value.toStringAsFixed(2)})',
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),

                          const SizedBox(height: 32),

                          // --- EXPENSE SECTION ---
                          const Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, color: Colors.redAccent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Expense',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '-$_currencySymbol${periodExpense.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (expenseCategories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Text(
                                'No expense recorded for this period',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            )
                          else
                            Column(
                              children: expenseCategories.entries.map((entry) {
                                final double percentage = periodExpense > 0
                                    ? (entry.value / periodExpense) * 100
                                    : 0;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A2642),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${percentage.toStringAsFixed(0)}%  ($_currencySymbol${entry.value.toStringAsFixed(2)})',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dedicated stateful widget that handles smooth level/height morphing animations
class SmoothAnimatedChart extends StatefulWidget {
  final List<TransactionModel> transactions;
  final int selectedMonth;
  final int selectedYear;
  final double? touchedX;
  final String currencySymbol;

  const SmoothAnimatedChart({
    super.key,
    required this.transactions,
    required this.selectedMonth,
    required this.selectedYear,
    required this.touchedX,
    required this.currencySymbol,
  });

  @override
  State<SmoothAnimatedChart> createState() => _SmoothAnimatedChartState();
}

class _SmoothAnimatedChartState extends State<SmoothAnimatedChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  List<double> _oldBalances = [];
  List<double> _currentBalances = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _currentBalances = _calculateFixedPoints(widget.transactions, widget.selectedYear, widget.selectedMonth);
    _oldBalances = List.from(_currentBalances);
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(SmoothAnimatedChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth ||
        oldWidget.selectedYear != widget.selectedYear ||
        oldWidget.transactions != widget.transactions) {

      _oldBalances = _evaluateCurrentInterpolatedBalances(_oldBalances, _currentBalances, _animation.value);
      _currentBalances = _calculateFixedPoints(widget.transactions, widget.selectedYear, widget.selectedMonth);

      _controller.forward(from: 0.0);
    }
  }

  List<double> _evaluateCurrentInterpolatedBalances(List<double> oldB, List<double> currB, double t) {
    List<double> result = [];
    for (int i = 0; i < 20; i++) {
      double o = i < oldB.length ? oldB[i] : 0.0;
      double c = i < currB.length ? currB[i] : 0.0;
      result.add(o + (c - o) * t);
    }
    return result;
  }

  /// Standardizes every month into 20 fixed points across time slices for smooth morphing
  List<double> _calculateFixedPoints(List<TransactionModel> txs, int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month, daysInMonth, 23, 59, 59);

    final sortedTx = List<TransactionModel>.from(txs)..sort((a, b) => a.date.compareTo(b.date));
    List<double> points = [];
    const int steps = 20;

    for (int i = 0; i < steps; i++) {
      double progress = i / (steps - 1);
      DateTime sliceTime = startDate.add(
        Duration(milliseconds: (endDate.difference(startDate).inMilliseconds * progress).toInt()),
      );

      double runningBalance = 0;
      for (var tx in sortedTx) {
        if (tx.date.isBefore(sliceTime) || tx.date.isAtSameMomentAs(sliceTime)) {
          if (tx.type == 'income') {
            runningBalance += tx.amount;
          } else {
            runningBalance -= tx.amount;
          }
        }
      }
      points.add(runningBalance);
    }
    return points;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _MorphingChartPainter(
            oldBalances: _oldBalances,
            currentBalances: _currentBalances,
            animationValue: _animation.value,
            touchedX: widget.touchedX,
            currencySymbol: widget.currencySymbol,
          ),
        );
      },
    );
  }
}

class _MorphingChartPainter extends CustomPainter {
  final List<double> oldBalances;
  final List<double> currentBalances;
  final double animationValue;
  final double? touchedX;
  final String currencySymbol;

  _MorphingChartPainter({
    required this.oldBalances,
    required this.currentBalances,
    required this.animationValue,
    required this.touchedX,
    required this.currencySymbol,
  });

  void _drawText(Canvas canvas, Offset position, String text, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    if (oldBalances.isEmpty || currentBalances.isEmpty) return;

    // Calculate Y heights for old balances
    double oldMax = oldBalances.reduce((a, b) => a > b ? a : b);
    double oldMin = oldBalances.reduce((a, b) => a < b ? a : b);
    double oldRange = (oldMax - oldMin) == 0 ? 1 : (oldMax - oldMin);

    // Calculate Y heights for current balances
    double currMax = currentBalances.reduce((a, b) => a > b ? a : b);
    double currMin = currentBalances.reduce((a, b) => a < b ? a : b);
    double currRange = (currMax - currMin) == 0 ? 1 : (currMax - currMin);

    // Interpolate overall max and min values for display labels
    double displayMax = oldMax + (currMax - oldMax) * animationValue;
    double displayMin = oldMin + (currMin - oldMin) * animationValue;

    List<Offset> points = [];
    List<double> currentValuesAtPoint = [];

    for (int i = 0; i < 20; i++) {
      double x = (i / 19) * size.width;

      // Old point Y position
      double oldNormY = (oldBalances[i] - oldMin) / oldRange;
      double oldY = size.height - (oldNormY * (size.height * 0.55) + size.height * 0.2);

      // Current point Y position
      double currNormY = (currentBalances[i] - currMin) / currRange;
      double currY = size.height - (currNormY * (size.height * 0.55) + size.height * 0.2);

      // Smoothly interpolate Y coordinates for visual level shift (up or down)
      double y = oldY + (currY - oldY) * animationValue;
      points.add(Offset(x, y));

      double val = oldBalances[i] + (currentBalances[i] - oldBalances[i]) * animationValue;
      currentValuesAtPoint.add(val);
    }

    // Grid reference lines
    final gridLinePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0;

    double maxYPos = size.height - (1.0 * (size.height * 0.55) + size.height * 0.2);
    double minYPos = size.height - (0.0 * (size.height * 0.55) + size.height * 0.2);

    canvas.drawLine(Offset(0, maxYPos), Offset(size.width, maxYPos), gridLinePaint);
    canvas.drawLine(Offset(0, minYPos), Offset(size.width, minYPos), gridLinePaint);

    _drawText(
      canvas,
      Offset(4, maxYPos - 14),
      'Peak: $currencySymbol${displayMax.toStringAsFixed(0)}',
      const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600),
    );
    _drawText(
      canvas,
      Offset(4, minYPos + 3),
      'Low: $currencySymbol${displayMin.toStringAsFixed(0)}',
      const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600),
    );

    // Draw Smooth Curve
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final controlPoint2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p2.dx, p2.dy);
    }

    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);

    // Render Touch Guideline & Floating Total Number Bubble
    if (touchedX != null && points.isNotEmpty) {
      double clampedX = touchedX!.clamp(0.0, size.width);
      int closestIndex = 0;
      double minDistance = double.infinity;

      for (int i = 0; i < points.length; i++) {
        double dist = (points[i].dx - clampedX).abs();
        if (dist < minDistance) {
          minDistance = dist;
          closestIndex = i;
        }
      }

      Offset closestPoint = points[closestIndex];
      double closestVal = currentValuesAtPoint[closestIndex];

      final guidePaint = Paint()
        ..color = Colors.white38
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(closestPoint.dx, 0), Offset(closestPoint.dx, size.height), guidePaint);

      final dotOuterPaint = Paint()..color = Colors.greenAccent.withOpacity(0.4);
      final dotInnerPaint = Paint()..color = Colors.greenAccent;
      canvas.drawCircle(closestPoint, 8, dotOuterPaint);
      canvas.drawCircle(closestPoint, 4, dotInnerPaint);

      String tooltipText = '$currencySymbol${closestVal.toStringAsFixed(2)}';
      TextPainter tp = TextPainter(
        text: TextSpan(
          text: tooltipText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();

      double tooltipWidth = tp.width + 16;
      double tooltipHeight = tp.height + 8;
      double tooltipX = (closestPoint.dx - tooltipWidth / 2).clamp(8.0, size.width - tooltipWidth - 8);
      double tooltipY = (closestPoint.dy - 36).clamp(4.0, size.height - tooltipHeight);

      RRect tooltipBg = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(8),
      );

      final bgPaint = Paint()..color = const Color(0xFF1E2D4A);
      final borderPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawRRect(tooltipBg, bgPaint);
      canvas.drawRRect(tooltipBg, borderPaint);
      tp.paint(canvas, Offset(tooltipX + 8, tooltipY + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _MorphingChartPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.touchedX != touchedX ||
        oldDelegate.currentBalances != currentBalances ||
        oldDelegate.oldBalances != oldBalances;
  }
}