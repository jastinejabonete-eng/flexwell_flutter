import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'camera_screen.dart';
import 'fade_route.dart';
import 'main_navigation_screen.dart';

class SummaryScreen extends StatelessWidget {
  final String exercise;
  final int accuracy;
  final int reps;
  final int longestHold;
  final bool isRepBased;
  // How many of the completed reps had zero incorrect-form frames during
  // their lifecycle (see CameraScreen's Fix #2: quality-tracked reps).
  // Only meaningful when isRepBased is true; defaults to 0 for hold-based
  // exercises / older call sites that haven't been updated yet.
  final int perfectReps;

  const SummaryScreen({
    super.key,
    required this.exercise,
    required this.accuracy,
    required this.reps,
    required this.longestHold,
    required this.isRepBased,
    this.perfectReps = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCardFilled : Colors.white;
    final primaryTextColor = isDark ? Colors.white : AppColors.lightText;
    final secondaryTextColor = isDark ? Colors.white54 : AppColors.lightTextSecondary;

    // Guard against out-of-range values so the ring and text never break.
    final safeAccuracy = accuracy.clamp(0, 100).toInt();
    final safeReps = reps < 0 ? 0 : reps;
    final safePerfect = perfectReps.clamp(0, safeReps).toInt();
    final safeHold = longestHold < 0 ? 0 : longestHold;

    // Dynamic fitness ring color based on accuracy score
    final statusColor = safeAccuracy >= 80
        ? AppColors.correct
        : (safeAccuracy >= 50 ? Colors.orange : AppColors.incorrect);

    // Only show the perfect-rep breakout for rep-based exercises where we
    // actually completed at least one rep — otherwise "0 / 0 perfect" is
    // just noise.
    final showPerfectReps = isRepBased && safeReps > 0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'SESSION COMPLETE',
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Never negative, even on very short screens.
                minHeight: (constraints.maxHeight - 32).clamp(0.0, double.infinity),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Target: $exercise',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Modern Fitness Accuracy Ring
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: safeAccuracy / 100,
                              strokeWidth: 16,
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.shade200,
                              color: statusColor,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$safeAccuracy%',
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                'Accuracy',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: secondaryTextColor,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Glass-style Stats Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isRepBased ? Icons.repeat_rounded : Icons.timer_rounded,
                                  color: isDark
                                      ? AppColors.accent
                                      : Colors.green.shade800,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isRepBased ? '$safeReps' : '${safeHold}s',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  Text(
                                    isRepBased
                                        ? 'Total Reps Completed'
                                        : 'Longest Perfect Hold',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Perfect-rep breakout: only rendered for rep-based
                          // exercises. Separated from the primary stat by a
                          // divider so it reads as a secondary, more granular
                          // metric rather than competing with the headline number.
                          if (showPerfectReps) ...[
                            const SizedBox(height: 20),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.grey.shade200,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.star_rounded,
                                    color: statusColor,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$safePerfect / $safeReps',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w900,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    Text(
                                      'Perfect-Form Reps',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const Spacer(),
                    const SizedBox(height: 16),

                    // Primary Action: Try Again (Volt Green)
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent, // Volt Green Gym color
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                          shadowColor: AppColors.accent.withValues(alpha: 0.4),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 24),
                        label: const Text(
                          'TRY AGAIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          fadeRoute(CameraScreen(exercise: exercise)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Secondary Action: Back to Dashboard
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey.shade400,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: Icon(
                          Icons.dashboard_rounded,
                          size: 20,
                          color: primaryTextColor,
                        ),
                        label: Text(
                          'BACK TO DASHBOARD',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                        onPressed: () => Navigator.pushAndRemoveUntil(
                          context,
                          fadeRoute(const MainNavigationScreen()),
                          (route) => false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}