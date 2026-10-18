import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'achievement_service.dart';
import 'app_colors.dart';
import 'onboarding_tour_steps.dart';

/// Key for the off-screen share card that gets captured to a PNG.
final GlobalKey _shareCardKey = GlobalKey();

/// Key for the off-screen single-badge share card.
final GlobalKey _badgeShareCardKey = GlobalKey();

class _Achievement {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final int order;
  const _Achievement(this.id, this.title, this.subtitle, this.icon, this.order);
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  // Streams for the global catalog and the user's specific unlocks
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _catalogStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _unlockedStream;

  // The badge currently being shared (null = sharing the overview card).
  // Set just before capture so the off-screen single-badge card renders the
  // correct badge.
  _Achievement? _shareBadge;

  // Live subscription to the user's unlocked badges. When a NEW badge id
  // appears (any badge, not just Share), we pop the celebration once. This
  // covers badges that land while viewing this screen (e.g. a session write
  // finishing, or the Share badge) so every unlock feels rewarded.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unlockedSub;
  final Set<String> _knownUnlocked = {};
  // Latest catalog snapshot, used to map a newly-unlocked id -> its title.
  List<_Achievement> _catalogCache = const [];
  // Ids queued to celebrate but not yet shown (dedupes rapid multi-unlocks).
  final ListQueue<String> _pendingCelebrations = ListQueue<String>();
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    // 1. Listen to the global achievements collection (managed by Admin PHP)
    _catalogStream = FirebaseFirestore.instance
        .collection('achievements')
        .orderBy('order')
        .snapshots();

    // 2. Listen to the specific user's unlocked badges
    final user = FirebaseAuth.instance.currentUser;
    _unlockedStream = user == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('unlocked_achievements')
              .snapshots();
    _unlockedSub = _unlockedStream?.listen(_onUnlockedSnapshot);
  }

  @override
  void dispose() {
    _unlockedSub?.cancel();
    super.dispose();
  }

  /// Fires the celebration popup for any badge id that appears for the first
  /// time in the unlocked stream. Skips the very first snapshot (those badges
  /// were unlocked in past sessions -- already celebrated then).
  void _onUnlockedSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final nowUnlocked = <String>{};
    for (final doc in snap.docs) {
      if (doc.data()['unlocked'] == true) nowUnlocked.add(doc.id);
    }
    // First emission: seed the known set, celebrate nothing.
    if (_knownUnlocked.isEmpty &&
        _pendingCelebrations.isEmpty &&
        !_seededUnlocked) {
      _knownUnlocked.addAll(nowUnlocked);
      _seededUnlocked = true;
      return;
    }
    final fresh = nowUnlocked.difference(_knownUnlocked);
    _knownUnlocked.addAll(nowUnlocked);
    for (final id in fresh) {
      _pendingCelebrations.add(id);
    }
    _drainCelebrations();
  }

  bool _seededUnlocked = false;

  /// Shows celebration popups one at a time (so they don't stack), pulling the
  /// badge title from the cached catalog.
  void _drainCelebrations() {
    if (_celebrating || _pendingCelebrations.isEmpty || !mounted) return;
    final id = _pendingCelebrations.removeFirst();
    final title = _catalogCache
        .firstWhere(
          (a) => a.id == id,
          orElse: () => _Achievement(id, id, '', Icons.star_rounded, 0),
        )
        .title;
    _celebrating = true;
    _showUnlockCelebration(title).then((_) {
      _celebrating = false;
      _drainCelebrations();
    });
  }

  /// The Share badge is identified by its catalog id. The live catalog uses
  /// 'share_achievement'; accept 'share' too so a renamed catalog still works.
  bool _isShareBadge(_Achievement item) =>
      item.id == 'share_achievement' || item.id == 'share';

  /// Translates the string iconName from Firestore into a Flutter IconData object.
  IconData _getIcon(String name) {
    switch (name) {
      case 'handshake_rounded':
        return Icons.handshake_rounded;
      case 'share_rounded':
        return Icons.ios_share_rounded;
      case 'workspace_premium_rounded':
        return Icons.workspace_premium_rounded;
      case 'fitness_center_rounded':
        return Icons.fitness_center_rounded;
      case 'shield_rounded':
        return Icons.shield_rounded;
      case 'verified_rounded':
        return Icons.verified_rounded;
      case 'bolt_rounded':
        return Icons.bolt_rounded;
      default:
        return Icons.star_rounded; // Fallback icon
    }
  }

  /// Parses the global catalog from Firestore into a list of _Achievement objects
  List<_Achievement> _parseCatalog(QuerySnapshot<Map<String, dynamic>>? snap) {
    if (snap == null) return [];
    return snap.docs.map((doc) {
      final data = doc.data();
      return _Achievement(
        doc.id,
        data['title'] ?? 'Unknown',
        data['subtitle'] ?? '',
        _getIcon(data['iconName'] ?? ''),
        data['order'] ?? 0,
      );
    }).toList();
  }

  /// id -> unlock time. A key that is present means "unlocked".
  /// A null value means the server timestamp hasn't resolved yet.
  Map<String, DateTime?> _parseUnlocked(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    final result = <String, DateTime?>{};
    if (snap == null) return result;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['unlocked'] == true) {
        final ts = data['unlockedAt'];
        result[doc.id] = ts is Timestamp ? ts.toDate() : null;
      }
    }
    return result;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Just now';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final suffix = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year % 100}, $h:$m $suffix';
  }

  /// Captures a share card to a PNG, writes it to a temp file, and opens the OS
  /// share sheet with that image. When [badge] is provided, shares a card for
  /// that single badge; otherwise shares the full achievements overview card.
  /// Unlocks the "share" achievement only on a completed share AND when the
  /// user already earned a workout badge.
  Future<void> _share(BuildContext context, {_Achievement? badge}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Render the correct off-screen card before capturing. setState rebuilds
      // the widget tree; the await on the microtask lets that frame lay out.
      setState(() => _shareBadge = badge);
      await WidgetsBinding.instance.endOfFrame;

      // 1. Capture the requested card to PNG bytes.
      final key = badge == null ? _shareCardKey : _badgeShareCardKey;
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Share card not ready — try again.')),
        );
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not render the share image.')),
        );
        return;
      }

      // 2. Write to a temp file (share_plus shares files, not raw bytes).
      final dir = await getTemporaryDirectory();
      final fileName = badge == null
          ? 'flexwell_achievements.png'
          : 'flexwell_${badge.id}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      // 3. Open the OS share sheet with the image + a caption.
      final caption = badge == null
          ? 'My FlexWell achievements! 💪'
          : 'I just earned the "${badge.title}" achievement on FlexWell! 💪';
      final result = await Share.shareXFiles([XFile(file.path)], text: caption);
      if (result.status == ShareResultStatus.success) {
        // The celebration popup is driven by the _unlockedStream listener
        // (_onUnlockedSnapshot) the moment the new badge doc lands -- so we
        // don't pop it here too, which would double up.
        await AchievementService.unlockShareAchievement();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Share cancelled.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the share sheet: $e')),
      );
    }
  }

  /// The off-screen card that gets captured to a shareable PNG. Shows the
  /// unlocked count, the app brand, and up to six earned badges. Kept in the
  /// widget tree (inside a RepaintBoundary) so it can always be captured.
  Widget _buildShareCard(
    List<_Achievement> catalog,
    Map<String, DateTime?> unlocked,
  ) {
    final earned = catalog.where((a) => unlocked.containsKey(a.id)).toList();
    final shown = earned.take(6).toList();
    return RepaintBoundary(
      key: _shareCardKey,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.accent,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'FLEXWELL',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 24,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'My Achievements',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${unlocked.length} / ${catalog.length} unlocked',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (shown.isEmpty)
              Text(
                'Start scanning to earn badges!',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              )
            else
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: shown
                    .map(
                      (a) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildShieldBadge(
                            icon: a.icon,
                            unlocked: true,
                            size: 44,
                            iconSize: 20,
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 70,
                            child: Text(
                              a.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 20),
            Text(
              'Train smart. Train safe.',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Big celebratory popup shown when a badge is newly unlocked from the
  /// Achievements screen. Mirrors the summary screen's gold-trophy style.
  /// Returns a Future that completes when the dialog is dismissed, so callers
  /// can queue the next celebration.
  Future<void> _showUnlockCelebration(String badgeTitle) async {
    final theme = Theme.of(context);
    final text = theme.colorScheme.onSurface;
    final subtext = theme.colorScheme.onSurfaceVariant;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Colors.black,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Badge Unlocked!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badgeTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check the Badges tab to see it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtext, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Awesome!',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The off-screen single-badge share card. Shows the FLEXWELL brand, the badge's
  /// shield + name + subtitle, and a footer. Captured to a PNG when the user
  /// taps Share inside that badge's detail dialog.
  Widget _buildBadgeShareCard(_Achievement badge) {
    return RepaintBoundary(
      key: _badgeShareCardKey,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.accent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'FLEXWELL',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 20,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _buildShieldBadge(
              icon: badge.icon,
              unlocked: true,
              size: 96,
              iconSize: 48,
            ),
            const SizedBox(height: 20),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              badge.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Achievement unlocked on FlexWell',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAchievementDetails(
    BuildContext context,
    _Achievement item,
    bool unlocked,
    DateTime? unlockedAt,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) {
        final cardBg = scheme.surface;
        final subtextColor = scheme.onSurfaceVariant;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Close badge details',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: Icon(Icons.close_rounded, color: subtextColor),
                  ),
                ),
                const SizedBox(height: 8),
                _buildShieldBadge(
                  icon: item.icon,
                  unlocked: unlocked,
                  size: 90,
                  iconSize: 44,
                ),
                const SizedBox(height: 24),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: unlocked ? AppColors.gold : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: subtextColor),
                ),
                const SizedBox(height: 6),
                Text(
                  unlocked ? _formatDate(unlockedAt) : 'Locked',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: unlocked
                          ? AppColors.gold
                          : scheme.surfaceContainerHighest,
                      foregroundColor: unlocked
                          ? Colors.black
                          : scheme.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: unlocked ? 4 : 0,
                    ),
                    // The Share badge is UNLOCKED BY sharing, so its button is
                    // always tappable (the earn-prerequisite is enforced in
                    // unlockShareAchievement). Every other locked badge stays
                    // disabled -- you can't share a badge you haven't earned.
                    onPressed: (unlocked || _isShareBadge(item))
                        ? () {
                            _share(context, badge: item);
                            Navigator.of(dialogContext).pop();
                          }
                        : null,
                    child: Text(
                      unlocked
                          ? 'Share'
                          : (_isShareBadge(item)
                                ? 'Share to unlock'
                                : 'Locked'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildShieldBadge({
    required IconData icon,
    required bool unlocked,
    double size = 60,
    double iconSize = 28,
  }) {
    const goldColor = AppColors.gold;
    const slateColor = AppColors.badgeLocked;

    return CustomPaint(
      size: Size(size, size * 1.15),
      painter: _ShieldPainter(color: unlocked ? goldColor : slateColor),
      child: SizedBox(
        width: size,
        height: size * 1.15,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: unlocked ? goldColor : slateColor,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nested StreamBuilders to combine Global Catalog and User Unlocks
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _catalogStream,
      builder: (context, catalogSnapshot) {
        final catalog = _parseCatalog(catalogSnapshot.data);
        // Keep a cache so the celebration can map a newly-unlocked id -> title.
        if (catalog.isNotEmpty) _catalogCache = catalog;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _unlockedStream,
          builder: (context, unlockedSnapshot) {
            final unlocked = _parseUnlocked(unlockedSnapshot.data);
            final hasError =
                catalogSnapshot.hasError || unlockedSnapshot.hasError;

            return _buildContent(
              context,
              catalog,
              unlocked,
              hasError: hasError,
            );
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<_Achievement> catalog,
    Map<String, DateTime?> unlocked, {
    required bool hasError,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final primaryTextColor = scheme.onSurface;
    final secondaryTextColor = scheme.onSurfaceVariant;

    // Sort latest unlocked achievements based on the dynamically loaded catalog
    final latest = catalog.where((a) => unlocked.containsKey(a.id)).toList()
      ..sort((a, b) {
        final da = unlocked[a.id] ?? DateTime.now();
        final db = unlocked[b.id] ?? DateTime.now();
        return db.compareTo(da);
      });
    final latestThree = latest.take(3).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [
          IconButton(
            tooltip: 'Share achievements',
            icon: Icon(Icons.share_rounded, color: primaryTextColor),
            onPressed: () => _share(context),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            // SingleChildScrollView has NO `padding` parameter -- passing one
            // compiles but is silently dropped, so the nav bar overlapped the
            // last badge row. Wrap the content in Padding instead.
            child: Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: 90,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Couldn\'t load your achievements. Check your connection.',
                        style: TextStyle(fontSize: 14, color: scheme.error),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '${unlocked.length} / ${catalog.length} unlocked',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppColors.lightBorder,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.2 : 0.05,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'LATEST ACHIEVEMENTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (catalog.isEmpty)
                          Text(
                            'Loading achievements catalog...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          )
                        else if (latestThree.isEmpty)
                          Text(
                            'Complete a scan to unlock your first badge.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          )
                        else
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 20,
                            runSpacing: 16,
                            children: latestThree.map((item) {
                              return Semantics(
                                button: true,
                                label: '${item.title}, unlocked',
                                onTap: () => _showAchievementDetails(
                                  context,
                                  item,
                                  true,
                                  unlocked[item.id],
                                ),
                                child: ExcludeSemantics(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => _showAchievementDetails(
                                        context,
                                        item,
                                        true,
                                        unlocked[item.id],
                                      ),
                                      child: SizedBox(
                                        width: 92,
                                        child: Column(
                                          children: [
                                            _buildShieldBadge(
                                              icon: item.icon,
                                              unlocked: true,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              item.title,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'ALL MILESTONES',
                    key: OnboardingTourAnchors.achievements,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 5
                          : constraints.maxWidth >= 600
                          ? 4
                          : 3;
                      final textScale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: catalog.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: (0.76 / textScale).clamp(
                            0.38,
                            0.76,
                          ),
                        ),
                        itemBuilder: (context, index) {
                          final item = catalog[index];
                          final isUnlocked = unlocked.containsKey(item.id);
                          void onTap() {
                            _showAchievementDetails(
                              context,
                              item,
                              isUnlocked,
                              unlocked[item.id],
                            );
                          }

                          return Semantics(
                            button: true,
                            label:
                                '${item.title} badge, ${isUnlocked ? 'unlocked' : 'locked'}',
                            onTap: onTap,
                            child: ExcludeSemantics(
                              child: Material(
                                color: cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isUnlocked
                                        ? AppColors.gold.withValues(alpha: 0.5)
                                        : (isDark
                                              ? AppColors.darkBorder
                                              : AppColors.lightBorder),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: onTap,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _buildShieldBadge(
                                          icon: item.icon,
                                          unlocked: isUnlocked,
                                          size: 48,
                                          iconSize: 22,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.title,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isUnlocked
                                                ? primaryTextColor
                                                : secondaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Off-screen share card: laid out so its RepaintBoundary can be
          // captured to a PNG, but positioned far above the viewport so it is
          // never visible. Positioned (not Opacity) keeps it paintable.
          Positioned(
            top: -10000,
            left: 0,
            child: _buildShareCard(catalog, unlocked),
          ),
          // Off-screen single-badge card for whichever badge is being shared
          // (set by _share just before capture). Positioned far above the
          // viewport so it is laid out and paintable but never visible.
          if (_shareBadge != null)
            Positioned(
              top: -10000,
              left: 0,
              child: _buildBadgeShareCard(_shareBadge!),
            ),
        ],
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  final Color color;

  _ShieldPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.2, 0);
    path.lineTo(w * 0.8, 0);
    path.lineTo(w, h * 0.2);
    path.lineTo(w, h * 0.6);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.6);
    path.lineTo(0, h * 0.2);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) =>
      oldDelegate.color != color;
}
