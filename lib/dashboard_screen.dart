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
      'iconColor': const Color(0xFF0096B2),
      'tag1': 'REPS',
      'tag2': 'Lower Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Push-Up',
      'subtitle': 'Chest & Triceps',
      'iconPath': 'assets/icons/pushup.svg',
      'iconColor': const Color(0xFFE72E8A),
      'tag1': 'REPS',
      'tag2': 'Upper Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Lunge',
      'subtitle': 'Legs & Core',
      'iconPath': 'assets/icons/lunge.svg',
      'iconColor': const Color(0xFFE9650C),
      'tag1': 'REPS',
      'tag2': 'Lower Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Pull-Up',
      'subtitle': 'Back & Biceps',
      'iconPath': 'assets/icons/pullup.svg',
      'iconColor': const Color(0xFF7D3EE6),
      'tag1': 'REPS',
      'tag2': 'Upper Body',
      'filter': 'Dynamic',
    },
    {
      'title': 'Plank',
      'subtitle': 'Core Endurance',
      'iconPath': 'assets/icons/plank.svg',
      'iconColor': const Color(0xFF008F82),
      'tag1': 'TIME',
      'tag2': 'Core',
      'filter': 'Static',
    },
    {
      'title': 'Side Plank',
      'subtitle': 'Abs & Core',
      'iconPath': 'assets/icons/sideplank.svg',
      'iconColor': const Color(0xFF7B4CE2),
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
      final now = DateTime.now();
      if (now.year != _now.year ||
          now.month != _now.month ||
          now.day != _now.day) {
        setState(() => _now = now);
      }
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
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('FlexWell'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HEADER ---
                        Text(
                          'Choose an exercise',
                          key: OnboardingTourAnchors.dashboardExercises,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose a movement to start a live form scan.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // --- SEARCH BAR ---
                      TextField(
                        key: OnboardingTourAnchors.dashboardSearch,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search exercises, muscle groups...',
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.secondaryTextFor(isDark),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkCardFilled
                              : AppColors.lightSurface,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
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
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _selectedFilter = filter);
                                  }
                                },
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? AppColors.accentFor(isDark)
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                backgroundColor: isDark
                                    ? AppColors.darkCardFilled
                                    : Colors.white,
                                selectedColor: AppColors.accentSubtleFor(
                                  isDark,
                                ),
                                side: BorderSide(
                                  color: isSelected
                                      ? AppColors.accentBorderFor(isDark)
                                      : (isDark
                                            ? AppColors.darkBorder
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                      ? (1.3 / textScale).clamp(0.8, 1.3)
                      : columns == 2
                      ? (0.82 / textScale).clamp(0.56, 0.82)
                      : (0.95 / textScale).clamp(0.68, 0.95);

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: _buildStreakSection(isDark),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final accentColor = AppColors.accentFor(isDark);
    final exercise = data['title'] as String;
    final iconColor = data['iconColor'] as Color;

    return Semantics(
      button: true,
      label: 'Start $exercise scan',
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCardFilled : AppColors.lightCard,
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
              if (await showExerciseCameraSetup(context, exercise) &&
                  context.mounted) {
                await Navigator.push(
                  context,
                  fadeRoute(CameraScreen(exercise: exercise)),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: iconColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgPicture.asset(
                          data['iconPath'],
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.videocam_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    exercise,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    '${data['tag1']}  ·  ${data['tag2']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_rounded,
                          color: isDark ? Colors.black : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Start scan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final color = AppColors.secondaryTextFor(isDark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardFilled : AppColors.lightCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
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

  static const List<String> _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const Color _volt = AppColors.brandSkyBlue;

  @override
  Widget build(BuildContext context) {
    final active = stats.current > 0;
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final weekStartUtc = DateTime.utc(
      now.year,
      now.month,
      now.day - (now.weekday % 7),
    );
    final activeDays = stats.days
        .where((day) => !day.isBefore(weekStartUtc) && !day.isAfter(todayUtc))
        .length;
    final textColor = AppColors.textFor(isDark);
    final subColor = AppColors.secondaryTextFor(isDark);
    final accentText = AppColors.accentFor(isDark);
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardFilled : AppColors.lightCard,
        borderRadius: BorderRadius.circular(18),
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
          // --- Current streak and a short status ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: flameColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  color: flameColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${stats.current}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
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
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
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
                Text(
                  'Best ${stats.best}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentText,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'This week',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),
              ),
              Text(
                '$activeDays active',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildWeek(textColor, subColor, accentText, borderColor),
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: worked ? AppColors.warmHighlight : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: worked
                      ? AppColors.brandBlue
                      : (isToday ? accentText : borderColor),
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Center(
                child: worked
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.lightText,
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
