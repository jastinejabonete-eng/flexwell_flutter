import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'app_colors.dart';
import 'camera_screen.dart';
import 'fade_route.dart';
import 'exercise_camera_setup_dialog.dart';
import 'firebase_status.dart';
import 'onboarding_tour_steps.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  // Every finished session is saved to users/{uid}/sessions with a 'dayKey'
  // (see AchievementService.recordSession). The streak is derived from those,
  // so it can never drift out of sync with what was actually recorded.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _sessionsStream;
  bool _retryingCloudHistory = false;

  // Search and Filter State
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final List<String> _filters = [
    'All',
    'Dynamic',
    'Static',
    'Upper Body',
    'Lower Body',
    'Core',
  ];

  // Exercise Data Catalog (6 Exercises with SVG paths)
  final List<Map<String, dynamic>> _allExercises = [
    {
      'title': 'Squat',
      'subtitle': 'Legs & Glutes',
      'iconPath': 'assets/icons/squat.svg',
      'accent': Colors.cyan,
      'tag1': 'REPS',
      'tag2': 'Lower Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Push-Up',
      'subtitle': 'Chest & Triceps',
      'iconPath': 'assets/icons/pushup.svg',
      'accent': Colors.purpleAccent,
      'tag1': 'REPS',
      'tag2': 'Upper Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Lunge',
      'subtitle': 'Legs & Core',
      'iconPath': 'assets/icons/lunge.svg',
      'accent': Colors.cyan,
      'tag1': 'REPS',
      'tag2': 'Lower Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Pull-Up',
      'subtitle': 'Back & Biceps',
      'iconPath': 'assets/icons/pullup.svg',
      'accent': Colors.purpleAccent,
      'tag1': 'REPS',
      'tag2': 'Upper Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Plank',
      'subtitle': 'Core Endurance',
      'iconPath': 'assets/icons/plank.svg',
      'accent': Colors.orangeAccent,
      'tag1': 'TIME',
      'tag2': 'Core',
      'filter': 'Static',
    },
    {
      'title': 'Side Plank',
      'subtitle': 'Abs & Core',
      'iconPath': 'assets/icons/sideplank.svg',
      'accent': Colors.orangeAccent,
      'tag1': 'TIME',
      'tag2': 'Core',
      'filter': 'Static',
    },
  ];

  @override
  void initState() {
    super.initState();
    _sessionsStream = _sessionsForCurrentUser();
    FirebaseStatus.authRevision.addListener(_onAuthenticationChanged);
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    FirebaseStatus.authRevision.removeListener(_onAuthenticationChanged);
    _timer.cancel();
    super.dispose();
  }

  void _onAuthenticationChanged() {
    if (!mounted) return;
    setState(() => _sessionsStream = _sessionsForCurrentUser());
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _sessionsForCurrentUser() {
    if (!FirebaseStatus.isInitialized) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .snapshots();
  }

  Future<void> _retryCloudHistory() async {
    if (_retryingCloudHistory) return;
    setState(() => _retryingCloudHistory = true);
    await FirebaseStatus.ensureSignedIn();
    if (!mounted) return;
    setState(() {
      _sessionsStream = _sessionsForCurrentUser();
      _retryingCloudHistory = false;
    });
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String dayName = days[dt.weekday - 1];
    String monthName = months[dt.month - 1];
    int hour = dt.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minute = dt.minute.toString().padLeft(2, '0');
    return '$dayName, $monthName ${dt.day} • $hour:$minute $period';
  }

  List<Map<String, dynamic>> get _filteredExercises {
    return _allExercises.where((ex) {
      final matchesSearch =
          ex['title'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          ex['subtitle'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );
      final matchesFilter =
          _selectedFilter == 'All' ||
          ex['filter'] == _selectedFilter ||
          ex['tag2'] == _selectedFilter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppColors.lightText;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDateTime(_now),
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'FlexWell',
              style: TextStyle(
                color: primaryTextColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- STREAK CARD (streak, best, this week, next milestone) ---
                  _buildStreakSection(isDark),

                  const SizedBox(height: 32),

                  // --- HEADER ---
                  Text(
                    'Choose an exercise',
                    key: OnboardingTourAnchors.dashboardExercises,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: primaryTextColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '6 exercises with real-time posture detection',
                    style: TextStyle(
                      color: isDark
                          ? Colors.white54
                          : AppColors.lightTextSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- SEARCH BAR ---
                  TextField(
                    key: OnboardingTourAnchors.dashboardSearch,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: primaryTextColor),
                    decoration: InputDecoration(
                      hintText: 'Search exercises, muscle groups...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark
                            ? Colors.white54
                            : AppColors.lightTextSecondary,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkCardFilled
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : AppColors.lightBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : AppColors.lightBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? AppColors.accent : AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- FILTER CHIPS ---
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _filters.map((filter) {
                        bool isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ChoiceChip(
                            label: Text(filter),
                            selected: isSelected,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedFilter = filter);
                              }
                            },
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : (isDark
                                        ? Colors.white
                                        : AppColors.lightText),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            backgroundColor: isDark
                                ? AppColors.darkCardFilled
                                : Colors.white,
                            selectedColor: AppColors.accent,
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.accent
                                  : (isDark
                                        ? Colors.white12
                                        : AppColors.lightBorder),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // --- EXERCISE GRID ---
          SliverLayoutBuilder(
            builder: (context, constraints) {
              if (_filteredExercises.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No exercises found',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try another search or clear your filters.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _selectedFilter = 'All';
                            });
                          },
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final width = constraints.crossAxisExtent;
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final columns = width < 360
                  ? 1
                  : width < 760
                  ? 2
                  : width < 1050
                  ? 3
                  : 4;
              final aspectRatio = columns == 1
                  ? (1.45 / textScale).clamp(0.55, 1.45)
                  : columns == 2
                  ? (1.0 / textScale).clamp(0.45, 1.0)
                  : (1.1 / textScale).clamp(0.42, 1.1);

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: aspectRatio,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildGridCard(
                      context,
                      _filteredExercises[index],
                      isDark,
                    ),
                    childCount: _filteredExercises.length,
                  ),
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    Color accentColor = data['accent'];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardFilled : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final exercise = data['title'] as String;
            if (await showExerciseCameraSetup(context, exercise) &&
                context.mounted) {
              await Navigator.push(
                context,
                fadeRoute(CameraScreen(exercise: exercise)),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SVG Icon Container
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SvgPicture.asset(
                    data['iconPath'],
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(accentColor, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  data['title'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data['subtitle'],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? Colors.white70
                        : AppColors.lightTextSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data['tag1'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.voltFor(isDark),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data['tag2'],
                          style: TextStyle(
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreakSection(bool isDark) {
    final stream = _sessionsStream;
    if (stream == null) {
      return _StreakStatusCard(
        isDark: isDark,
        message:
            'Workout history is unavailable while cloud services are offline.',
        isLoading: _retryingCloudHistory,
        onRetry: _retryCloudHistory,
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StreakStatusCard(
            isDark: isDark,
            message:
                'Could not load workout history. Your streak could not be checked.',
            isLoading: _retryingCloudHistory,
            onRetry: _retryCloudHistory,
          );
        }
        if (!snapshot.hasData) {
          return _StreakStatusCard(
            isDark: isDark,
            message: 'Loading workout history…',
            isLoading: true,
          );
        }
        final keys = <String>[];
        for (final doc in snapshot.data!.docs) {
          final day = doc.data()['dayKey'];
          if (day is String) keys.add(day);
        }
        return _StreakCard(
          stats: _StreakStats.fromDayKeys(keys, _now),
          now: _now,
          isDark: isDark,
        );
      },
    );
  }
}

class _StreakStatusCard extends StatelessWidget {
  final bool isDark;
  final String message;
  final bool isLoading;
  final VoidCallback? onRetry;

  const _StreakStatusCard({
    required this.isDark,
    required this.message,
    this.isLoading = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : AppColors.lightTextSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardFilled : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.cloud_off_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(color: color, height: 1.4)),
                if (onRetry != null) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: isLoading ? null : onRetry,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STREAK
// ============================================================================

/// Streak numbers derived from the 'dayKey' (yyyy-MM-dd, local time) saved with
/// every session. Uses the same day boundaries as AchievementService, so the
/// dashboard and the "Determination" badge always agree.
class _StreakStats {
  final int current;
  final int best;
  final bool doneToday;
  final Set<DateTime> days; // UTC midnights, one per day with a workout

  const _StreakStats({
    required this.current,
    required this.best,
    required this.doneToday,
    required this.days,
  });

  /// The streak is still alive but nothing has been logged yet today.
  bool get atRisk => current > 0 && !doneToday;

  bool hasWorkedOn(DateTime d) =>
      days.contains(DateTime.utc(d.year, d.month, d.day));

  factory _StreakStats.fromDayKeys(Iterable<String> keys, DateTime now) {
    DateTime? parse(String key) {
      final parts = key.split('-');
      if (parts.length != 3) return null;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime.utc(y, m, d); // UTC avoids DST skewing day differences
    }

    final days = keys.map(parse).whereType<DateTime>().toSet();
    final today = DateTime.utc(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final doneToday = days.contains(today);

    // Current streak: walk back from today (or yesterday if today is still
    // open). A gap of a full day ends it.
    var cursor = doneToday ? today : yesterday;
    var current = 0;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    // Best streak: longest run of consecutive days in the whole history.
    final sorted = days.toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final d in sorted) {
      run = (previous != null && d.difference(previous).inDays == 1)
          ? run + 1
          : 1;
      if (run > best) best = run;
      previous = d;
    }

    return _StreakStats(
      current: current,
      best: best,
      doneToday: doneToday,
      days: days,
    );
  }
}

class _StreakCard extends StatelessWidget {
  final _StreakStats stats;
  final DateTime now;
  final bool isDark;

  const _StreakCard({
    required this.stats,
    required this.now,
    required this.isDark,
  });

  static const List<int> _milestones = [3, 7, 14, 30, 60, 100];
  static const List<String> _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const Color _volt = AppColors.accent;

  @override
  Widget build(BuildContext context) {
    final active = stats.current > 0;
    final textColor = isDark ? Colors.white : AppColors.lightText;
    final subColor = isDark ? Colors.white60 : AppColors.lightTextSecondary;
    final accentText = isDark ? _volt : AppColors.primary;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.lightBorder;

    final Color flameColor;
    if (!active) {
      flameColor = isDark ? Colors.white30 : Colors.black26;
    } else if (stats.atRisk) {
      flameColor = Colors.orangeAccent;
    } else {
      flameColor = isDark ? _volt : Colors.green.shade700;
    }

    final String message;
    if (!active) {
      message = stats.days.isEmpty
          ? 'Finish a workout today to light your first streak.'
          : 'Your streak reset. Finish a workout today to start a new one.';
    } else if (stats.doneToday) {
      message =
          'Done for today. Come back tomorrow to make it ${stats.current + 1}.';
    } else {
      message =
          'Work out today to keep your ${stats.current}-day streak alive.';
    }

    // Progress toward the next milestone, measured from the previous one.
    int? next;
    var previous = 0;
    for (final m in _milestones) {
      if (m > stats.current) {
        next = m;
        break;
      }
      previous = m;
    }
    final progress = next == null
        ? 1.0
        : (stats.current - previous) / (next - previous);
    final daysToGo = next == null ? 0 : next - stats.current;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardFilled : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: !active
              ? borderColor
              : (stats.atRisk
                    ? Colors.orangeAccent.withValues(alpha: 0.6)
                    : accentText.withValues(alpha: 0.4)),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Headline: flame, count, message, best ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: flameColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  color: flameColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: stats.current.toDouble()),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Text(
                            '${value.round()}',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'day streak',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: stats.atRisk ? Colors.orangeAccent : subColor,
                        fontWeight: stats.atRisk
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (stats.best > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentText.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 14,
                        color: accentText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Best ${stats.best}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 18),

          // --- This week ---
          _buildWeek(textColor, subColor, accentText, borderColor),

          const SizedBox(height: 18),

          // --- Next milestone ---
          Row(
            children: [
              Expanded(
                child: Text(
                  next == null
                      ? 'Top milestone reached: ${_milestones.last} days'
                      : 'Next milestone: $next-day streak',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              if (next != null)
                Text(
                  '$daysToGo ${daysToGo == 1 ? 'day' : 'days'} to go',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.lightBorder,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? _volt : AppColors.accentDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeek(
    Color textColor,
    Color subColor,
    Color accentText,
    Color borderColor,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    // Weeks start on Sunday (weekday 7 % 7 == 0).
    final startOfWeek = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday % 7),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final day = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day + index,
        );
        final isToday = day == today;
        final isFuture = day.isAfter(today);
        final worked = stats.hasWorkedOn(day);

        return Column(
          children: [
            Text(
              _dayLabels[index],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isToday ? textColor : subColor,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: worked ? _volt : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: worked ? _volt : (isToday ? accentText : borderColor),
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Center(
                child: worked
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.black,
                        size: 20,
                      )
                    : Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isFuture
                              ? (isDark ? Colors.white24 : Colors.black26)
                              : (isToday ? accentText : subColor),
                        ),
                      ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
