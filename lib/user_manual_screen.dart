import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'exercise_camera_guide.dart';
import 'onboarding_tour_steps.dart';

// -----------------------------------------------------------------------------
// Content
// -----------------------------------------------------------------------------

class _Badge {
  final IconData icon;
  final String name;
  final String how;
  const _Badge(this.icon, this.name, this.how);
}

const List<_Badge> _badges = [
  _Badge(
    Icons.workspace_premium_rounded,
    'First Milestone',
    'Finish your first workout scan.',
  ),
  _Badge(
    Icons.fitness_center_rounded,
    'Determination',
    'Work out 3 days in a row.',
  ),
  _Badge(Icons.shield_rounded, 'Iron Core', 'Hold a Plank for 60 seconds.'),
  _Badge(
    Icons.verified_rounded,
    'Form Master',
    'Score over 90% accuracy in a Squat session.',
  ),
  _Badge(Icons.bolt_rounded, 'Gym Warrior', 'Scan all 6 exercises.'),
  _Badge(
    Icons.star_rounded,
    'Flawless Form',
    'Finish 5 reps with perfect form in one session.',
  ),
  _Badge(Icons.handshake_rounded, 'Share', 'Tap Share on the Badges tab.'),
];

const List<(String, String)> _quickStart = [
  (
    'Pick an exercise',
    'Choose one on the Dashboard, or tap Scan Now under a tutorial video.',
  ),
  (
    'Set up your phone',
    'Prop it up so your whole body is in frame. Check the camera angle for your exercise below.',
  ),
  (
    'Move and watch the skeleton',
    'Green means good form. Red means adjust, and a tip appears on screen.',
  ),
  (
    'Tap Stop when you finish',
    'You get your accuracy score, plus your reps or your longest hold.',
  ),
];

class _Tone {
  final bool isDark;
  final Color text;
  final Color sub;
  final Color card;
  final Color border;
  final Color accent;
  final Color accentBorder;

  _Tone(ThemeData theme)
    : isDark = theme.brightness == Brightness.dark,
      text = theme.colorScheme.onSurface,
      sub = theme.colorScheme.onSurfaceVariant,
      card = theme.colorScheme.surface,
      border = theme.colorScheme.outlineVariant,
      accent = theme.colorScheme.primary,
      accentBorder = AppColors.accentBorderFor(
        theme.brightness == Brightness.dark,
      );
}

// -----------------------------------------------------------------------------
// Screen
// -----------------------------------------------------------------------------

class UserManualScreen extends StatefulWidget {
  const UserManualScreen({super.key});

  @override
  State<UserManualScreen> createState() => _UserManualScreenState();
}

class _UserManualScreenState extends State<UserManualScreen> {
  bool _showGoodForm = true;
  int _guideIndex = 0;

  @override
  Widget build(BuildContext context) {
    final t = _Tone(Theme.of(context));

    return Scaffold(
      backgroundColor: t.isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(title: const Text('User manual')),
      body: ListView(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: 100,
        ),
        children: [
          _hero(t),
          const SizedBox(height: 28),

          _sectionHeader(
            t,
            'Quick start',
            'Four steps from tapping an exercise to your first score.',
          ),
          KeyedSubtree(
            key: OnboardingTourAnchors.manualQuickStart,
            child: _quickStartCard(t),
          ),
          const SizedBox(height: 28),

          _sectionHeader(
            t,
            'Reading the skeleton',
            'Tap each one to see what you will get on screen.',
          ),
          _formPreview(t),
          const SizedBox(height: 28),

          _sectionHeader(
            t,
            'Where to put your camera',
            'The form check is trained on specific views, so the angle matters.',
          ),
          _cameraGuide(t),
          const SizedBox(height: 28),

          _sectionHeader(t, 'Tips for better tracking', null),
          _tips(t),
          const SizedBox(height: 28),

          _sectionHeader(t, 'Streaks and badges', 'Small habits add up.'),
          _streaksAndBadges(t),
          const SizedBox(height: 28),

          _sectionHeader(t, 'Tutorials', null),
          _tutorialsCard(t),
          const SizedBox(height: 28),

          _sectionHeader(t, 'Troubleshooting', null),
          _faq(
            t,
            'The skeleton stays red the whole time',
            'Check your camera angle against the guide above. The form check expects a left-side or back view depending on the exercise, so the wrong angle can read as bad form.',
          ),
          _faq(
            t,
            'It says "Can\'t see you clearly"',
            'Some of the joints it needs are hidden or too dim to track. Step back, turn on more light, and make sure your whole body is in frame.',
          ),
          _faq(
            t,
            'It says "Calibrating"',
            'Squat, Push-Up and Pull-Up calibrate from a stable one-second window. Hold the required starting pose still and keep all the joints listed in the camera guide visible.',
          ),
          _faq(
            t,
            'My workout did not count toward my streak',
            'A session needs about 3 seconds of tracked movement. If you tap Stop right after starting, nothing is saved.',
          ),
          _faq(
            t,
            'Is my video saved?',
            'Pose tracking runs on your phone. Only your session results are saved to your account: exercise, accuracy, reps and hold time.',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  Widget _card(_Tone t, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(_Tone t, String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: t.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: t.sub, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _choice(_Tone t, String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      labelStyle: TextStyle(
        color: selected
            ? (t.isDark ? AppColors.darkBackground : Colors.white)
            : t.text,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: t.isDark
          ? AppColors.darkCardFilled
          : AppColors.lightRaised,
      selectedColor: t.accent,
      side: BorderSide(color: selected ? t.accentBorder : t.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _pill(_Tone t, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.brandSkyBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: t.accent,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  Widget _hero(_Tone t) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.isDark ? AppColors.darkCardFilled : AppColors.brandBlue,
        borderRadius: BorderRadius.circular(20),
        border: t.isDark
            ? Border.all(color: AppColors.brandSkyBlue.withValues(alpha: 0.25))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brandSkyBlue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.brandSkyBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Your form coach, one tap away',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Set up your phone, read the skeleton, and keep your streak going.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(Icons.fitness_center_rounded, '6 exercises'),
              _heroChip(Icons.visibility_rounded, 'Live feedback'),
              _heroChip(Icons.bolt_rounded, 'On-device AI'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.brandSkyBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickStartCard(_Tone t) {
    return _card(
      t,
      Column(
        children: [
          for (var i = 0; i < _quickStart.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: t.isDark
                                ? AppColors.darkBackground
                                : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (i < _quickStart.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: t.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < _quickStart.length - 1 ? 18 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _quickStart[i].$1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _quickStart[i].$2,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: t.sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _formPreview(_Tone t) {
    final good = _showGoodForm;
    final color = good ? AppColors.correct : AppColors.incorrect;

    return _card(
      t,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              _choice(
                t,
                'Good form',
                good,
                () => setState(() => _showGoodForm = true),
              ),
              _choice(
                t,
                'Needs work',
                !good,
                () => setState(() => _showGoodForm = false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(good),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.accessibility_new_rounded, size: 48, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          good ? 'Green skeleton' : 'Red skeleton',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          good
                              ? 'On-screen message: "Good form"'
                              : 'On-screen message (Squat): "Check your depth and keep your chest up"',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: t.sub,
                          ),
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
  }

  Widget _cameraGuide(_Tone t) {
    final guides = ExerciseCameraGuide.all;
    final g = guides[_guideIndex];

    return _card(
      t,
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < guides.length; i++)
                  _choice(
                    t,
                    guides[i].exercise,
                    i == _guideIndex,
                    () => setState(() => _guideIndex = i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(t, Icons.videocam_rounded, g.view),
                _pill(
                  t,
                  g.repBased ? Icons.repeat_rounded : Icons.timer_rounded,
                  g.repBased ? 'Counts reps' : 'Times your hold',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              g.setup,
              style: TextStyle(fontSize: 14, height: 1.5, color: t.text),
            ),
            if (g.calibrates) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: t.sub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hold your starting position for about a second. The app shows "Calibrating" while it learns your baseline.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: t.sub,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tipTile(_Tone t, IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.accent, size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: t.sub),
          ),
        ],
      ),
    );
  }

  Widget _tips(_Tone t) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _tipTile(
                  t,
                  Icons.light_mode_rounded,
                  'Good lighting',
                  'Face a light source. Dim rooms make tracking drop out.',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tipTile(
                  t,
                  Icons.straighten_rounded,
                  'Give it space',
                  'Stand a couple of metres back so you fit head to toe.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _tipTile(
                  t,
                  Icons.checkroom_rounded,
                  'Fitted clothes',
                  'Baggy clothes can hide your joints from the tracker.',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tipTile(
                  t,
                  Icons.person_rounded,
                  'Just you in frame',
                  'One person in view keeps the skeleton on you.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ruleLine(_Tone t, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streaksAndBadges(_Tone t) {
    return _card(
      t,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How your streak works',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          _ruleLine(
            t,
            Icons.local_fire_department_rounded,
            'Finish a workout to add a day. Several workouts in one day still count as one day.',
          ),
          _ruleLine(
            t,
            Icons.schedule_rounded,
            'A workout needs about 3 seconds of tracked movement to count.',
          ),
          _ruleLine(
            t,
            Icons.warning_amber_rounded,
            'Miss a whole day and your streak starts over. The Dashboard warns you when it is at risk.',
          ),
          Divider(color: t.border, height: 28),
          Text(
            'Badges to earn',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _badges.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < _badges.length - 1 ? 12 : 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_badges[i].icon, size: 20, color: t.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _badges[i].name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        Text(
                          _badges[i].how,
                          style: TextStyle(fontSize: 12.5, color: t.sub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tutorialsCard(_Tone t) {
    return _card(
      t,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.play_circle_fill_rounded, color: t.accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Open the Tutorials tab and tap a card to watch a short demo of the movement. The video plays right inside the card. When you are ready, tap Scan Now to jump straight into the camera.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: t.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _faq(_Tone t, String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: t.accent,
          collapsedIconColor: t.sub,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          children: [
            Text(
              answer,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: t.sub),
            ),
          ],
        ),
      ),
    );
  }
}
