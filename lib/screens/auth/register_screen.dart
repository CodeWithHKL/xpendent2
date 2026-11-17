import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static bool isRegistering = false;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();

  late AnimationController _successAnimController;
  late Animation<double> _cardScaleAnim;
  late Animation<double> _checkScaleAnim;
  late Animation<double> _ringPulseAnim;
  late Animation<double> _textFadeAnim;
  late Animation<Offset> _textSlideAnim;
  late Animation<double> _redirectProgressAnim;

  // Step 1 Controllers
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Step 2 Controllers (Optional)
  final _universityController = TextEditingController();
  final _universityFocusNode = FocusNode();
  String? _selectedYear;

  int _currentStep = 0;
  bool _isLoading = false;
  bool _isCheckingStepOne = false;
  bool _showSuccessOverlay = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Shows Step 1 Error Messages
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  final List<String> _yearOptions = [
    'Foundation / Diploma',
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year+',
    'Postgraduate',
  ];

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

  // Password security rule checks
  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasUppercase => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => _passwordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar =>
      _passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]'));

  int get _passwordScore {
    int score = 0;
    if (_hasMinLength) score++;
    if (_hasUppercase) score++;
    if (_hasLowercase) score++;
    if (_hasDigit) score++;
    if (_hasSpecialChar) score++;
    return score;
  }

  String get _passwordStrengthLabel {
    if (_passwordController.text.isEmpty) return '';
    if (_passwordScore <= 2) return 'Weak';
    if (_passwordScore == 3) return 'Fair';
    if (_passwordScore == 4) return 'Good';
    return 'Strong';
  }

  Color get _passwordStrengthColor {
    if (_passwordScore <= 2) return Colors.redAccent;
    if (_passwordScore == 3) return Colors.orangeAccent;
    if (_passwordScore == 4) return const Color(0xFF00C897);
    return const Color(0xFF00E676);
  }

  bool get _isPasswordSecureEnough => _passwordScore >= 4;

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _cardScaleAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: const Interval(0.0, 0.22, curve: Curves.easeOutBack),
    );

    _checkScaleAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: const Interval(0.10, 0.38, curve: Curves.elasticOut),
    );

    _ringPulseAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: const Interval(0.12, 0.55, curve: Curves.easeOutCubic),
    );

    _textFadeAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: const Interval(0.20, 0.42, curve: Curves.easeOut),
    );

    _textSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _successAnimController,
        curve: const Interval(0.20, 0.42, curve: Curves.easeOutCubic),
      ),
    );

    _redirectProgressAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: const Interval(0.25, 1.0, curve: Curves.linear),
    );
  }

  bool _isValidEmailFormat(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  Future<bool> _isEmailAlreadyRegistered(String email) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) return true;
    } catch (_) {}

    try {
      final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      if (methods.isNotEmpty) return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        rethrow;
      }
    } catch (_) {}

    return false;
  }

  @override
  void dispose() {
    RegisterScreen.isRegistering = false;
    _successAnimController.dispose();
    _pageController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _universityController.dispose();
    _universityFocusNode.dispose();
    super.dispose();
  }

  Future<void> _goToNextStep() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    String? usernameErr;
    String? emailErr;
    String? passwordErr;
    String? confirmErr;

    if (username.isEmpty) {
      usernameErr = 'Please enter a username.';
    } else if (username.length < 3) {
      usernameErr = 'Username must be at least 3 characters.';
    }

    if (email.isEmpty) {
      emailErr = 'Please enter your email address.';
    } else if (!_isValidEmailFormat(email)) {
      emailErr = 'Invalid email format (e.g. name@example.com).';
    }

    if (password.isEmpty) {
      passwordErr = 'Please create a password.';
    } else if (!_isPasswordSecureEnough) {
      passwordErr = 'Password is too weak. Meet at least 4 requirements (Good/Strong).';
    }

    if (confirmPassword.isEmpty) {
      confirmErr = 'Please confirm your password.';
    } else if (password != confirmPassword) {
      confirmErr = 'Passwords do not match.';
    }

    setState(() {
      _usernameError = usernameErr;
      _emailError = emailErr;
      _passwordError = passwordErr;
      _confirmPasswordError = confirmErr;
    });

    if (usernameErr != null ||
        emailErr != null ||
        passwordErr != null ||
        confirmErr != null) {
      return;
    }

    setState(() => _isCheckingStepOne = true);
    try {
      final alreadyRegistered = await _isEmailAlreadyRegistered(email);
      if (alreadyRegistered) {
        if (mounted) {
          setState(() {
            _emailError = 'This email is already registered. Please log in or use another email.';
          });
        }
        return;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _emailError = e.code == 'invalid-email'
              ? 'Invalid email format. Please check your email address.'
              : (e.message ?? 'Unable to verify email address.');
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _isCheckingStepOne = false);
    }

    FocusScope.of(context).unfocus();
    setState(() => _currentStep = 1);
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToPreviousStep() {
    FocusScope.of(context).unfocus();
    setState(() => _currentStep = 0);
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeRegistration({bool skipOptional = false}) async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final university = skipOptional ? '' : _universityController.text.trim();
    final year = skipOptional ? '' : (_selectedYear ?? '');

    FocusScope.of(context).unfocus();
    RegisterScreen.isRegistering = true;
    setState(() => _isLoading = true);

    try {
      await _authService.registerUser(email, password);

      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await currentUser.updateDisplayName(username);

        await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
          'displayName': username,
          'email': email,
          if (university.isNotEmpty) 'university': university,
          if (year.isNotEmpty) 'year': year,
          'currencyCode': 'MYR',
          'currencySymbol': 'RM',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Sign out immediately so the user is NOT logged in automatically
      await FirebaseAuth.instance.signOut();
      RegisterScreen.isRegistering = false;

      if (!mounted) return;

      // Play the success animation and then return to LoginScreen
      setState(() {
        _isLoading = false;
        _showSuccessOverlay = true;
      });

      await _successAnimController.forward();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      RegisterScreen.isRegistering = false;
      if (mounted) {
        setState(() => _isLoading = false);
        if (e.code == 'email-already-in-use' || e.code == 'invalid-email') {
          setState(() {
            _emailError = e.code == 'email-already-in-use'
                ? 'This email is already registered. Please use another email.'
                : 'Invalid email format. Please enter a valid email.';
          });
          _goToPreviousStep();
        } else {
          _showSnackBar(e.message ?? 'Registration failed.');
        }
      }
    } catch (e) {
      RegisterScreen.isRegistering = false;
      if (mounted) {
        setState(() => _isLoading = false);
        final message = e.toString();
        if (message.contains('email-already-in-use')) {
          setState(() {
            _emailError = 'This email is already registered. Please use another email.';
          });
          _goToPreviousStep();
        } else {
          _showSnackBar('Registration failed: $message');
        }
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return AnimatedOpacity(
      opacity: _showSuccessOverlay ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 280),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF0A1120).withOpacity(0.92),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Center(
          child: ScaleTransition(
            scale: _cardScaleAnim,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E2F50),
                    Color(0xFF13203A),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF00C897).withOpacity(0.45),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C897).withOpacity(0.18),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Pulsing Ring + Elastic Checkmark Badge
                  SizedBox(
                    width: 108,
                    height: 108,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _ringPulseAnim,
                          builder: (context, _) {
                            final scale = 0.75 + (_ringPulseAnim.value * 0.45);
                            final opacity = (1.0 - _ringPulseAnim.value).clamp(0.0, 1.0);
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF00C897).withOpacity(opacity * 0.8),
                                    width: 3,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        ScaleTransition(
                          scale: _checkScaleAnim,
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF00E676),
                                  Color(0xFF00C897),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00C897).withOpacity(0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF0F1A2E),
                              size: 46,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Animated Title & Subtitle
                  FadeTransition(
                    opacity: _textFadeAnim,
                    child: SlideTransition(
                      position: _textSlideAnim,
                      child: Column(
                        children: const [
                          Text(
                            'Account Registered!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Your account has been created successfully.\nRedirecting you to the login page...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Animated Redirect Progress Bar
                  AnimatedBuilder(
                    animation: _redirectProgressAnim,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _redirectProgressAnim.value,
                          minHeight: 5,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00C897),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
    bool hasError = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      prefixIcon: Icon(
        prefixIcon,
        color: hasError ? Colors.redAccent : Colors.white54,
        size: 20,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1E2D48).withOpacity(0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.redAccent : const Color(0xFF2C3E61),
          width: hasError ? 1.5 : 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? Colors.redAccent : const Color(0xFF2575FC),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildFieldErrorText(String? errorMessage) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: errorMessage != null
          ? Padding(
        padding: const EdgeInsets.only(top: 6.0, left: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 14,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                errorMessage,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildPasswordRuleItem(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          AnimatedScale(
            scale: isMet ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                key: ValueKey<bool>(isMet),
                size: 15,
                color: isMet ? const Color(0xFF00C897) : Colors.white38,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isMet ? FontWeight.w500 : FontWeight.normal,
                color: isMet ? Colors.white : Colors.white38,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedPasswordChecker() {
    final bool hasText = _passwordController.text.isNotEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: hasText
          ? AnimatedOpacity(
        opacity: hasText ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Password Security:',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _passwordStrengthLabel,
                      key: ValueKey<String>(_passwordStrengthLabel),
                      style: TextStyle(
                        color: _passwordStrengthColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (index) {
                  final bool active = index < _passwordScore;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 240 + (index * 35)),
                      curve: Curves.easeOutCubic,
                      height: active ? 6 : 4,
                      margin: EdgeInsets.only(right: index < 4 ? 5 : 0),
                      decoration: BoxDecoration(
                        color: active ? _passwordStrengthColor : Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: active
                            ? [
                          BoxShadow(
                            color: _passwordStrengthColor.withOpacity(0.45),
                            blurRadius: 6,
                            spreadRadius: 0.5,
                          ),
                        ]
                            : [],
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2D48).withOpacity(0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isPasswordSecureEnough
                        ? const Color(0xFF00C897).withOpacity(0.4)
                        : Colors.white10,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPasswordRuleItem('At least 8 characters', _hasMinLength),
                    _buildPasswordRuleItem('Contains uppercase letter (A-Z)', _hasUppercase),
                    _buildPasswordRuleItem('Contains lowercase letter (a-z)', _hasLowercase),
                    _buildPasswordRuleItem('Contains at least one number (0-9)', _hasDigit),
                    _buildPasswordRuleItem('Contains special symbol (!@#\$%^&*)', _hasSpecialChar),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildUniversityAutocompleteField() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: _universityController,
          focusNode: _universityFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) {
              return const Iterable<String>.empty();
            }

            final startsWithMatches = _universitySuggestions
                .where((uni) => uni.toLowerCase().startsWith(query))
                .toList();
            final containsMatches = _universitySuggestions
                .where((uni) =>
            !uni.toLowerCase().startsWith(query) &&
                uni.toLowerCase().contains(query))
                .toList();

            return [...startsWithMatches, ...containsMatches];
          },
          onSelected: (String selection) {
            _universityController.text = selection;
            setState(() {});
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: _buildInputDecoration(
                hintText: 'Start typing e.g. UNITEN, UM, UPM...',
                prefixIcon: Icons.school_outlined,
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                )
                    : null,
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Material(
                  color: const Color(0xFF192A47),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: const Color(0xFF192A47),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2575FC).withOpacity(0.5)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: Colors.white10,
                      ),
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.account_balance_outlined,
                                  size: 16,
                                  color: Color(0xFF00C897),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
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
    );
  }

  Widget _buildStepOneAccountDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Create Account',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Step 1 of 2 • Set up your profile & strong password',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 28),

          // Username
          const Text(
            'Username',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_usernameError != null) {
                setState(() => _usernameError = null);
              }
            },
            decoration: _buildInputDecoration(
              hintText: 'Enter your username',
              prefixIcon: Icons.person_outline,
              hasError: _usernameError != null,
            ),
          ),
          _buildFieldErrorText(_usernameError),

          const SizedBox(height: 16),

          // Email
          const Text(
            'Email Address',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
            decoration: _buildInputDecoration(
              hintText: 'Enter your email address',
              prefixIcon: Icons.email_outlined,
              hasError: _emailError != null,
            ),
          ),
          _buildFieldErrorText(_emailError),

          const SizedBox(height: 16),

          // Password
          const Text(
            'Password',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {
              _passwordError = null;
            }),
            decoration: _buildInputDecoration(
              hintText: 'Create a strong password',
              prefixIcon: Icons.lock_outline,
              hasError: _passwordError != null,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          _buildFieldErrorText(_passwordError),

          // Smooth Animated Password Strength Meter & Rules
          _buildAnimatedPasswordChecker(),

          const SizedBox(height: 16),

          // Confirm Password
          const Text(
            'Confirm Password',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) {
              if (_confirmPasswordError != null) {
                setState(() => _confirmPasswordError = null);
              }
            },
            decoration: _buildInputDecoration(
              hintText: 'Re-enter your password',
              prefixIcon: Icons.verified_user_outlined,
              hasError: _confirmPasswordError != null,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
          _buildFieldErrorText(_confirmPasswordError),

          const SizedBox(height: 28),

          // Next Step Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isCheckingStepOne ? null : _goToNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2575FC),
                disabledBackgroundColor: const Color(0xFF2575FC).withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCheckingStepOne
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
                  : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Next',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                text: const TextSpan(
                  text: 'Already have an account? ',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  children: [
                    TextSpan(
                      text: 'Log In',
                      style: TextStyle(
                        color: Color(0xFF2575FC),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStepTwoAcademicDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Row(
            children: [
              Text(
                'Student Details',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Chip(
                label: Text(
                  'Optional',
                  style: TextStyle(color: Color(0xFF00C897), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                backgroundColor: Color(0xFF1E2D48),
                side: BorderSide(color: Color(0xFF00C897), width: 0.8),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Step 2 of 2 • Personalize your profile (you can skip this)',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 32),

          // University Field with Autocomplete Hints (Optional)
          const Text(
            'University / Institution (Optional)',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _buildUniversityAutocompleteField(),

          const SizedBox(height: 20),

          // Year of Study Dropdown (Optional)
          const Text(
            'Year of Study (Optional)',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2D48).withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2C3E61)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedYear,
                isExpanded: true,
                dropdownColor: const Color(0xFF192A47),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                hint: const Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 19),
                    SizedBox(width: 12),
                    Text(
                      'Select your current year',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
                items: _yearOptions.map((String year) {
                  return DropdownMenuItem<String>(
                    value: year,
                    child: Text(
                      year,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedYear = val),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Create Account Button
          _isLoading
              ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C897)),
          )
              : Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _completeRegistration(skipOptional: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C897),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Complete Registration',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F1A2E),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => _completeRegistration(skipOptional: true),
                child: const Text(
                  'Skip for now & Finish',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showSuccessOverlay && !_isLoading,
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF192A47),
                    Color(0xFF0F1A2E),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Top AppBar with Back Navigation & Animated Step Indicator
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: _isLoading
                                ? null
                                : () {
                              if (_currentStep == 1) {
                                _goToPreviousStep();
                              } else {
                                Navigator.pop(context);
                              }
                            },
                          ),
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                                width: _currentStep == 0 ? 32 : 24,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2575FC),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                                width: _currentStep == 1 ? 32 : 24,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _currentStep == 1
                                      ? const Color(0xFF00C897)
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),

                    // Two-Page Registration Flow
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStepOneAccountDetails(),
                          _buildStepTwoAcademicDetails(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Animated Account Registered Overlay
            if (_showSuccessOverlay) _buildSuccessOverlay(),
          ],
        ),
      ),
    );
  }
}