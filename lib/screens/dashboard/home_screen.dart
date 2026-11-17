import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/transaction_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../tabs/share_screen.dart';
import '../tabs/goal_screen.dart';
import '../tabs/profile_screen.dart';
import '../tabs/balance_screen.dart';
import '../analytics/analytics_screen.dart';
import '../budget/budget_management_screen.dart';

typedef DateRange = Map<String, DateTime>;

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;
  final FirestoreService _firestoreService = FirestoreService();

  // Cached streams so profile updates never recreate inner StreamBuilders
  late final Stream<DocumentSnapshot> _profileStream;
  late final Stream<List<TransactionModel>> _transactionsStream;
  late final Stream<QuerySnapshot> _customCategoriesStream;

  int _selectedYear = DateTime.now().year;
  late final ValueNotifier<int> _selectedMonthNotifier;

  final ScrollController _verticalTimelineScrollController = ScrollController();
  final GlobalKey _timelineViewportKey = GlobalKey();
  final List<GlobalKey> _monthKeys = List.generate(12, (_) => GlobalKey());
  bool _isProgrammaticScroll = false;
  bool _hasInitialScrolled = false;
  String? _lastCurrencyCode;

  final List<String> _monthImages = [
    'assets/Jan.png',
    'assets/Feb.png',
    'assets/Mar.png',
    'assets/Apr.png',
    'assets/May.png',
    'assets/Jun.png',
    'assets/Jul.png',
    'assets/Aug.png',
    'assets/Sep.png',
    'assets/Oct.png',
    'assets/Nov.png',
    'assets/Dec.png',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _selectedMonthNotifier = ValueNotifier<int>(DateTime.now().month);
    _verticalTimelineScrollController.addListener(_onTimelineScroll);

    _profileStream = _firestoreService.getUserProfile(widget.user.uid);
    _transactionsStream = _firestoreService.getTransactions(widget.user.uid);
    _customCategoriesStream = _firestoreService.getCustomCategories(widget.user.uid);
  }

  @override
  void dispose() {
    _verticalTimelineScrollController.removeListener(_onTimelineScroll);
    _pageController.dispose();
    _selectedMonthNotifier.dispose();
    _verticalTimelineScrollController.dispose();
    super.dispose();
  }

  String _getDisplayCurrency(String? txCurrencyCode, String profileSymbol) {
    if (txCurrencyCode == null || txCurrencyCode.isEmpty) {
      return profileSymbol;
    }
    switch (txCurrencyCode.toUpperCase()) {
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
        return txCurrencyCode;
    }
  }

  Future<void> _jumpToInitialMonth() async {
    if (_hasInitialScrolled) return;
    final int targetIndex = (_selectedMonthNotifier.value - 1).clamp(0, 11);
    final BuildContext? keyContext = _monthKeys[targetIndex].currentContext;
    if (keyContext != null) {
      _hasInitialScrolled = true;
      _isProgrammaticScroll = true;
      await Scrollable.ensureVisible(
        keyContext,
        duration: Duration.zero,
        alignment: 0.0,
      );
      _isProgrammaticScroll = false;
    }
  }

  void _onTimelineScroll() {
    if (_isProgrammaticScroll ||
        !_hasInitialScrolled ||
        !_verticalTimelineScrollController.hasClients) {
      return;
    }

    final RenderBox? viewportBox =
    _timelineViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;

    final double viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final double triggerLine = viewportTop + 75.0;

    int detectedMonth = _selectedMonthNotifier.value;

    final position = _verticalTimelineScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 12) {
      detectedMonth = 12;
    } else {
      for (int i = 0; i < _monthKeys.length; i++) {
        final RenderBox? monthBox =
        _monthKeys[i].currentContext?.findRenderObject() as RenderBox?;
        if (monthBox != null && monthBox.hasSize) {
          final double sectionTop = monthBox.localToGlobal(Offset.zero).dy;
          if (sectionTop <= triggerLine) {
            detectedMonth = i + 1;
          } else {
            break;
          }
        }
      }
    }

    if (_selectedMonthNotifier.value != detectedMonth) {
      _selectedMonthNotifier.value = detectedMonth;
    }
  }

  Future<void> _onTabTapped(int index) async {
    if (_currentIndex == index) return;

    final int previousIndex = _currentIndex;
    final int distance = (previousIndex - index).abs();

    if (index == 0) {
      final now = DateTime.now();
      _selectedYear = now.year;
      _selectedMonthNotifier.value = now.month;
      _hasInitialScrolled = false;
      _isProgrammaticScroll = true;
    }

    setState(() {
      _currentIndex = index;
    });

    if (distance == 1) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    } else {
      final int intermediatePage = index > previousIndex ? index - 1 : index + 1;
      _pageController.jumpToPage(intermediatePage);
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    if (index == 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _jumpToInitialMonth();
        }
      });
    }
  }

  Route _createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
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

  IconData _getCategoryIcon(String category, Map<String, dynamic>? customData) {
    if (customData != null && customData['iconCodePoint'] != null) {
      return IconData(customData['iconCodePoint'], fontFamily: 'MaterialIcons');
    }
    switch (category) {
      case 'Supermarket':
        return Icons.shopping_cart;
      case 'Clothing':
        return Icons.checkroom;
      case 'Entertainment':
        return Icons.ondemand_video;
      case 'Transport':
        return Icons.directions_bus;
      case 'Education':
        return Icons.school;
      case 'Travel':
        return Icons.flight;
      case 'Food':
        return Icons.fastfood;
      case 'House':
        return Icons.home;
      case 'Allowance/Sponsorship':
        return Icons.account_balance_wallet;
      case 'Family':
        return Icons.family_restroom;
      case 'Part-Time Job':
        return Icons.work_outline;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Color _getCategoryColor(String category, Map<String, dynamic>? customData) {
    if (customData != null && customData['colorValue'] != null) {
      return Color(customData['colorValue']);
    }
    switch (category) {
      case 'Supermarket':
        return Colors.redAccent;
      case 'Clothing':
        return Colors.lightBlueAccent;
      case 'Entertainment':
        return Colors.purpleAccent;
      case 'Transport':
        return Colors.cyanAccent;
      case 'Education':
        return Colors.tealAccent;
      case 'Travel':
        return Colors.pinkAccent;
      case 'Food':
        return Colors.orangeAccent;
      case 'House':
        return Colors.white70;
      case 'Allowance/Sponsorship':
        return Colors.blueAccent;
      case 'Family':
        return Colors.pinkAccent;
      case 'Part-Time Job':
        return Colors.greenAccent;
      default:
        return Colors.white70;
    }
  }

  Future<void> _scrollToMonthSection(int monthIndex) async {
    final BuildContext? keyContext = _monthKeys[monthIndex].currentContext;
    if (keyContext != null) {
      _isProgrammaticScroll = true;
      await Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.0,
      );
      _isProgrammaticScroll = false;
    }
  }

  List<DateTime> _getMonthsForYear(int year) {
    return List.generate(12, (index) => DateTime(year, index + 1, 1));
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
              width: 320,
              height: 340,
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
                          });
                          Navigator.pop(context);
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

  List<DateRange> _getWeeklyRanges(int year, int month) {
    final List<DateRange> ranges = [];
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final List<int> breakPoints = [1, 4, 11, 18, 25, daysInMonth + 1];

    for (int i = 0; i < breakPoints.length - 1; i++) {
      final int startDay = breakPoints[i];
      final int endDay = breakPoints[i + 1] - 1;
      if (startDay <= daysInMonth) {
        ranges.add({
          'start': DateTime(year, month, startDay),
          'end': DateTime(year, month, endDay, 23, 59, 59),
        });
      }
    }
    return ranges;
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    Widget? customIcon,
  }) {
    final bool isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            customIcon ??
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF6C5CE7) : Colors.grey,
                  size: 24,
                ),
            AnimatedClipRect(
              open: isSelected,
              horizontal: true,
              vertical: false,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6C5CE7),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthsList = _getMonthsForYear(_selectedYear);

    Widget calendarView = Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _profileStream,
        builder: (context, profileSnapshot) {
          String currencySymbol = 'RM';

          if (profileSnapshot.hasData && profileSnapshot.data!.data() != null) {
            final profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
            final String? newCurrencyCode = profileData['currencyCode'] as String?;

            if (_lastCurrencyCode != null &&
                newCurrencyCode != null &&
                _lastCurrencyCode != newCurrencyCode) {
              final now = DateTime.now();
              _selectedYear = now.year;
              _selectedMonthNotifier.value = now.month;
              _hasInitialScrolled = false;
            }
            _lastCurrencyCode = newCurrencyCode;

            if (profileData['currencySymbol'] != null &&
                (profileData['currencySymbol'] as String).isNotEmpty) {
              currencySymbol = profileData['currencySymbol'] as String;
            } else if (newCurrencyCode != null) {
              currencySymbol = _getDisplayCurrency(newCurrencyCode, 'RM');
            }
          }

          return StreamBuilder<List<TransactionModel>>(
            stream: _transactionsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allTransactions = snapshot.data ?? [];

              return StreamBuilder<QuerySnapshot>(
                stream: _customCategoriesStream,
                builder: (context, customSnapshot) {
                  final Map<String, Map<String, dynamic>> customDataMap = {};
                  if (customSnapshot.hasData && customSnapshot.data != null) {
                    for (var doc in customSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final title = data['title'] as String?;
                      if (title != null) {
                        customDataMap[title] = data;
                      }
                    }
                  }

                  if (!_hasInitialScrolled) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _jumpToInitialMonth();
                      }
                    });
                  }

                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
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
                                        colors: [Color(0xFF132247), Color(0xFF0C1327)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.only(top: 8, bottom: 12),
                              color: Colors.black.withOpacity(0.15),
                              child: SafeArea(
                                bottom: false,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          GestureDetector(
                                            onTap: () async {
                                              await Navigator.push(
                                                context,
                                                _createSlideRightRoute(
                                                  ProfileScreen(user: widget.user),
                                                ),
                                              );
                                              if (mounted && !_hasInitialScrolled) {
                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                  if (mounted) {
                                                    _jumpToInitialMonth();
                                                  }
                                                });
                                              }
                                            },
                                            child: const CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.white10,
                                              child: Icon(Icons.person_outline, color: Colors.white, size: 20),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                _createSlideRightRoute(
                                                  BudgetManagementScreen(
                                                    user: widget.user,
                                                    initialMonth: _selectedMonthNotifier.value,
                                                    initialYear: _selectedYear,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: const CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.white10,
                                              child: Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _showYearPicker,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                children: [
                                                  ValueListenableBuilder<int>(
                                                    valueListenable: _selectedMonthNotifier,
                                                    builder: (context, selectedMonth, _) {
                                                      String monthName = DateFormat('MMMM')
                                                          .format(DateTime(_selectedYear, selectedMonth));
                                                      return AnimatedSwitcher(
                                                        duration: const Duration(milliseconds: 250),
                                                        transitionBuilder: (child, animation) {
                                                          return FadeTransition(
                                                            opacity: animation,
                                                            child: SlideTransition(
                                                              position: Tween<Offset>(
                                                                begin: const Offset(0.0, 0.2),
                                                                end: Offset.zero,
                                                              ).animate(animation),
                                                              child: child,
                                                            ),
                                                          );
                                                        },
                                                        child: Text(
                                                          '$monthName Balance',
                                                          key: ValueKey('$selectedMonth-$_selectedYear'),
                                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                                ],
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                _createSlideRightRoute(
                                                  AnalyticsScreen(user: widget.user),
                                                ),
                                              );
                                            },
                                            child: const CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.white10,
                                              child: Icon(Icons.show_chart, color: Colors.white, size: 20),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _showSignOutConfirmation,
                                            child: const CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.white10,
                                              child: Icon(Icons.logout, color: Colors.white, size: 20),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    ValueListenableBuilder<int>(
                                      valueListenable: _selectedMonthNotifier,
                                      builder: (context, selectedMonth, _) {
                                        final monthTxs = allTransactions.where((tx) =>
                                        tx.date.year == _selectedYear && tx.date.month == selectedMonth);
                                        double inc = 0, exp = 0;
                                        for (var tx in monthTxs) {
                                          if (tx.type == 'income') {
                                            inc += tx.amount;
                                          } else {
                                            exp += tx.amount;
                                          }
                                        }
                                        final double net = inc - exp;

                                        return TweenAnimationBuilder<double>(
                                          tween: Tween<double>(end: net),
                                          duration: const Duration(milliseconds: 380),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, animatedNet, _) {
                                            final double displayValue =
                                            animatedNet.abs() < 0.005 ? 0.0 : animatedNet;
                                            final String sign = displayValue >= 0 ? '+' : '-';

                                            return Text(
                                              '$sign$currencySymbol${displayValue.abs().toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    _HorizontalMonthBar(
                                      monthsList: monthsList,
                                      selectedMonthNotifier: _selectedMonthNotifier,
                                      onMonthSelected: (index, monthNum) {
                                        _selectedMonthNotifier.value = monthNum;
                                        _scrollToMonthSection(index);
                                      },
                                    ),

                                    const SizedBox(height: 12),

                                    ValueListenableBuilder<int>(
                                      valueListenable: _selectedMonthNotifier,
                                      builder: (context, selectedMonth, _) {
                                        final monthTxs = allTransactions.where((tx) =>
                                        tx.date.year == _selectedYear && tx.date.month == selectedMonth);
                                        double inc = 0, exp = 0;
                                        for (var tx in monthTxs) {
                                          if (tx.type == 'income') {
                                            inc += tx.amount;
                                          } else {
                                            exp += tx.amount;
                                          }
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1E2D4A).withOpacity(0.85),
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.archive_outlined,
                                                          color: Colors.greenAccent, size: 20),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Text('Income',
                                                                style: TextStyle(color: Colors.white70, fontSize: 11)),
                                                            TweenAnimationBuilder<double>(
                                                              tween: Tween<double>(end: inc),
                                                              duration: const Duration(milliseconds: 380),
                                                              curve: Curves.easeOutCubic,
                                                              builder: (context, animatedInc, _) {
                                                                return Text(
                                                                  '+$currencySymbol${animatedInc.abs().toStringAsFixed(2)}',
                                                                  style: const TextStyle(
                                                                      color: Colors.greenAccent,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 14),
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1E2D4A).withOpacity(0.85),
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.shopping_bag_outlined,
                                                          color: Colors.redAccent, size: 20),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Text('Expenses',
                                                                style: TextStyle(color: Colors.white70, fontSize: 11)),
                                                            TweenAnimationBuilder<double>(
                                                              tween: Tween<double>(end: exp),
                                                              duration: const Duration(milliseconds: 380),
                                                              curve: Curves.easeOutCubic,
                                                              builder: (context, animatedExp, _) {
                                                                return Text(
                                                                  '-$currencySymbol${animatedExp.abs().toStringAsFixed(2)}',
                                                                  style: const TextStyle(
                                                                      color: Colors.redAccent,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 14),
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        key: _timelineViewportKey,
                        child: SingleChildScrollView(
                          controller: _verticalTimelineScrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            children: List.generate(12, (monthIndex) {
                              final int monthNum = monthIndex + 1;
                              final DateTime currentMonthDate = DateTime(_selectedYear, monthNum, 1);
                              final String monthTitle = DateFormat('MMMM yyyy').format(currentMonthDate);

                              final String monthImagePath = _monthImages[monthIndex];
                              final weeklyRanges = _getWeeklyRanges(_selectedYear, monthNum);

                              return Column(
                                key: _monthKeys[monthIndex],
                                children: [
                                  Container(
                                    height: 150,
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 16),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Image.asset(
                                            monthImagePath,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.brown.shade800,
                                                      Colors.deepOrange.shade900,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.black.withOpacity(0.3),
                                          ),
                                        ),
                                        Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.65),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.white24),
                                            ),
                                            child: Text(
                                              monthTitle,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  Container(
                                    color: const Color(0xFF0F1626),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    child: Column(
                                      children: weeklyRanges.map((range) {
                                        final DateTime start = range['start']!;
                                        final DateTime end = range['end']!;

                                        final weekTransactions = allTransactions.where((tx) {
                                          return tx.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
                                              tx.date.isBefore(end.add(const Duration(seconds: 1)));
                                        }).toList();

                                        final String dateRangeLabel =
                                            '${DateFormat('MMM dd').format(start)} - ${DateFormat('dd').format(end)}';

                                        final Map<String, List<TransactionModel>> groupedByDay = {};
                                        for (var tx in weekTransactions) {
                                          final String dayKey = DateFormat('dd MMM|EEEE').format(tx.date);
                                          if (!groupedByDay.containsKey(dayKey)) {
                                            groupedByDay[dayKey] = [];
                                          }
                                          groupedByDay[dayKey]!.add(tx);
                                        }

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              child: Center(
                                                child: Text(
                                                  dateRangeLabel,
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            ...groupedByDay.entries.map((entry) {
                                              final List<String> parts = entry.key.split('|');
                                              final String dayHeader = parts[0];
                                              final String weekDay = parts[1];

                                              final dayTransactions = List<TransactionModel>.from(entry.value)
                                                ..sort((a, b) => a.date.compareTo(b.date));

                                              return Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          dayHeader,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          weekDay,
                                                          style: const TextStyle(
                                                            color: Colors.white38,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  ...dayTransactions.map((tx) {
                                                    final bool isIncome = tx.type == 'income';
                                                    final customData = customDataMap[tx.category];
                                                    final categoryIcon = _getCategoryIcon(tx.category, customData);
                                                    final categoryColor = _getCategoryColor(tx.category, customData);
                                                    final itemCurrency = _getDisplayCurrency(
                                                      tx.currencyCode,
                                                      currencySymbol,
                                                    );

                                                    return GestureDetector(
                                                      onTap: () {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => TransactionDetailScreen(
                                                              userId: widget.user.uid,
                                                              transaction: tx,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      child: Container(
                                                        margin: const EdgeInsets.only(bottom: 8),
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 16, vertical: 14),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1A2642),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              categoryIcon,
                                                              color: categoryColor,
                                                              size: 22,
                                                            ),
                                                            const SizedBox(width: 14),
                                                            Expanded(
                                                              child: Text(
                                                                tx.title,
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 14,
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                            Text(
                                                              '$itemCurrency ${tx.amount.toStringAsFixed(2)}',
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Container(
                                                              padding: const EdgeInsets.all(2),
                                                              decoration: BoxDecoration(
                                                                color: isIncome ? Colors.green : Colors.redAccent,
                                                                shape: BoxShape.circle,
                                                              ),
                                                              child: Icon(
                                                                isIncome ? Icons.add : Icons.remove,
                                                                color: Colors.white,
                                                                size: 10,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              );
                                            }),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: _ExpandableFabMenu(
        userId: widget.user.uid,
      ),
    );

    final List<Widget> pages = [
      calendarView,
      ShareScreen(user: widget.user),
      GoalScreen(user: widget.user),
      BalanceScreen(user: widget.user),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F1626),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: pages,
      ),
      bottomNavigationBar: Container(
        height: 65,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF132247),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(index: 0, icon: Icons.calendar_month, label: 'Calendar'),
            _buildNavItem(
              index: 1,
              icon: Icons.share,
              label: 'Share',
              customIcon: ShareNavBadgeIcon(
                user: widget.user,
                isSelected: _currentIndex == 1,
                inactiveColor: Colors.grey,
              ),
            ),
            _buildNavItem(index: 2, icon: Icons.track_changes, label: 'Goal'),
            _buildNavItem(index: 3, icon: Icons.account_balance_wallet, label: 'Balance'),
          ],
        ),
      ),
    );
  }
}

class AnimatedClipRect extends StatelessWidget {
  final Widget child;
  final bool open;
  final bool horizontal;
  final bool vertical;
  final Duration duration;
  final Curve curve;

  const AnimatedClipRect({
    super.key,
    required this.child,
    required this.open,
    this.horizontal = true,
    this.vertical = false,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeInOut,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: curve,
      tween: Tween<double>(begin: open ? 0.0 : 1.0, end: open ? 1.0 : 0.0),
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: horizontal ? value : 1.0,
            heightFactor: vertical ? value : 1.0,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _HorizontalMonthBar extends StatefulWidget {
  final List<DateTime> monthsList;
  final ValueNotifier<int> selectedMonthNotifier;
  final Function(int index, int monthNum) onMonthSelected;

  const _HorizontalMonthBar({
    required this.monthsList,
    required this.selectedMonthNotifier,
    required this.onMonthSelected,
  });

  @override
  State<_HorizontalMonthBar> createState() => _HorizontalMonthBarState();
}

class _HorizontalMonthBarState extends State<_HorizontalMonthBar> {
  final ScrollController _barController = ScrollController();
  late final List<GlobalKey> _itemKeys;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(
      widget.monthsList.length,
          (_) => GlobalKey(),
    );

    widget.selectedMonthNotifier.addListener(_onMonthChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCenter(widget.selectedMonthNotifier.value - 1);
    });
  }

  @override
  void dispose() {
    widget.selectedMonthNotifier.removeListener(_onMonthChanged);
    _barController.dispose();
    super.dispose();
  }

  void _onMonthChanged() {
    _scrollToCenter(widget.selectedMonthNotifier.value - 1);
  }

  void _scrollToCenter(int index) {
    if (index < 0 || index >= _itemKeys.length || !_barController.hasClients) return;

    final context = _itemKeys[index].currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final position = box.localToGlobal(Offset.zero, ancestor: this.context.findRenderObject());
        final itemWidth = box.size.width;
        final screenWidth = MediaQuery.of(this.context).size.width;

        final targetOffset = _barController.offset + position.dx - (screenWidth / 2) + (itemWidth / 2);

        _barController.animateTo(
          targetOffset.clamp(0.0, _barController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ValueListenableBuilder<int>(
        valueListenable: widget.selectedMonthNotifier,
        builder: (context, selectedMonth, _) {
          return Center(
            child: SingleChildScrollView(
              controller: _barController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.monthsList.length, (index) {
                  final monthDate = widget.monthsList[index];
                  bool isSelected = monthDate.month == selectedMonth;
                  String monthLabel =
                      '${DateFormat('MMM').format(monthDate).toUpperCase()} ${DateFormat('yy').format(monthDate)}';

                  return GestureDetector(
                    key: _itemKeys[index],
                    onTap: () {
                      widget.onMonthSelected(index, monthDate.month);
                      _scrollToCenter(index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2E3E6E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          monthLabel,
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
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExpandableFabMenu extends StatefulWidget {
  final String userId;
  const _ExpandableFabMenu({super.key, required this.userId});

  @override
  State<_ExpandableFabMenu> createState() => _ExpandableFabMenuState();
}

class _ExpandableFabMenuState extends State<_ExpandableFabMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      value: 0.0,
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnim = CurvedAnimation(
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
      parent: _animController,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  void _onOptionTap(String type) {
    _toggleMenu();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(
          userId: widget.userId,
          initialType: type,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SlideTransition(
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _onOptionTap('expense'),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3E6E),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_outlined, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Expense',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SlideTransition(
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _onOptionTap('income'),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3E6E),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.archive_outlined, color: Colors.greenAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Income',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        FloatingActionButton(
          backgroundColor: const Color(0xFF6C5CE7),
          onPressed: _toggleMenu,
          child: RotationTransition(
            turns: Tween<double>(begin: 0.0, end: 0.125).animate(_animController),
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}