import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'achievement_service.dart';
import 'app_colors.dart';

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
  }

  /// Translates the string iconName from Firestore into a Flutter IconData object.
  IconData _getIcon(String name) {
    switch (name) {
      case 'handshake_rounded': return Icons.handshake_rounded;
      case 'workspace_premium_rounded': return Icons.workspace_premium_rounded;
      case 'fitness_center_rounded': return Icons.fitness_center_rounded;
      case 'shield_rounded': return Icons.shield_rounded;
      case 'verified_rounded': return Icons.verified_rounded;
      case 'bolt_rounded': return Icons.bolt_rounded;
      default: return Icons.star_rounded; // Fallback icon
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
  Map<String, DateTime?> _parseUnlocked(QuerySnapshot<Map<String, dynamic>>? snap) {
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
      final fileName =
          badge == null ? 'flexwell_achievements.png' : 'flexwell_${badge.id}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      // 3. Open the OS share sheet with the image + a caption.
      final caption = badge == null
          ? 'My FlexWell achievements! 💪'
          : 'I just earned the "${badge.title}" achievement on FlexWell! 💪';
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: caption,
      );
      if (result.status == ShareResultStatus.success) {
        final unlocked = await AchievementService.unlockShareAchievement();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              unlocked
                  ? 'Thanks for sharing! Badge unlocked.'
                  : 'Thanks for sharing! Earn a workout badge first to unlock the Share badge.',
            ),
          ),
        );
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
  Widget _buildShareCard(List<_Achievement> catalog, Map<String, DateTime?> unlocked) {
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
                Icon(Icons.fitness_center_rounded, color: AppColors.accent, size: 28),
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
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
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
                    .map((a) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildShieldBadge(icon: a.icon, unlocked: true, size: 44, iconSize: 20),
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
                        ))
                    .toList(),
              ),
            const SizedBox(height: 20),
            Text(
              'Train smart. Train safe.',
              style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// Off-screen single-badge share card. Shows the FLEXWELL brand, the badge's
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
                Icon(Icons.fitness_center_rounded, color: AppColors.accent, size: 24),
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
            _buildShieldBadge(icon: badge.icon, unlocked: true, size: 96, iconSize: 48),
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
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            Text(
              'Achievement unlocked on FlexWell',
              style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) {
        final cardBg = isDark ? AppColors.darkCardFilled : Colors.white;
        final subtextColor = isDark ? Colors.white70 : AppColors.lightTextSecondary;

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
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Icon(Icons.close_rounded, color: subtextColor, size: 24),
                  ),
                ),
                const SizedBox(height: 8),
                _buildShieldBadge(icon: item.icon, unlocked: unlocked, size: 90, iconSize: 44),
                const SizedBox(height: 24),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: unlocked ? AppColors.gold : Colors.grey.shade400,
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: unlocked
                          ? AppColors.gold
                          : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      foregroundColor: unlocked ? Colors.black : Colors.grey.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: unlocked ? 4 : 0,
                    ),
                    onPressed: unlocked
                        ? () {
                            _share(context, badge: item);
                            Navigator.of(dialogContext).pop();
                          }
                        : null,
                    child: Text(
                      unlocked ? 'Share' : 'Locked',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          child: Icon(icon, size: iconSize, color: unlocked ? goldColor : slateColor),
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

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _unlockedStream,
          builder: (context, unlockedSnapshot) {
            final unlocked = _parseUnlocked(unlockedSnapshot.data);
            final hasError = catalogSnapshot.hasError || unlockedSnapshot.hasError;
            
            return _buildContent(context, catalog, unlocked, hasError: hasError);
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context, 
    List<_Achievement> catalog, 
    Map<String, DateTime?> unlocked, 
    {required bool hasError}
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCardFilled : Colors.white;
    final primaryTextColor = isDark ? Colors.white : AppColors.lightText;
    final secondaryTextColor = isDark ? Colors.white54 : AppColors.lightTextSecondary;

    // Sort latest unlocked achievements based on the dynamically loaded catalog
    final latest = catalog.where((a) => unlocked.containsKey(a.id)).toList()
      ..sort((a, b) {
        final da = unlocked[a.id] ?? DateTime.now();
        final db = unlocked[b.id] ?? DateTime.now();
        return db.compareTo(da);
      });
    final latestThree = latest.take(3).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          'Achievements',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.ios_share_rounded, color: primaryTextColor),
            onPressed: () => _share(context),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 90),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Couldn\'t load your achievements. Check your connection.',
                  style: TextStyle(fontSize: 12, color: AppColors.incorrect),
                ),
              ),
            Row(
              children: [
                Text(
                  '${unlocked.length} / ${catalog.length} unlocked',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.lightBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
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
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    )
                  else if (latestThree.isEmpty)
                    Text(
                      'Complete a scan to unlock your first badge.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: latestThree.map((item) {
                        return GestureDetector(
                          onTap: () => _showAchievementDetails(context, item, true, unlocked[item.id]),
                          child: Column(
                            children: [
                              _buildShieldBadge(icon: item.icon, unlocked: true),
                              const SizedBox(height: 12),
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryTextColor,
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
            const SizedBox(height: 28),
            Text(
              'ALL MILESTONES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: catalog.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 14,
                mainAxisSpacing: 20,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (context, index) {
                final item = catalog[index];
                final isUnlocked = unlocked.containsKey(item.id);

                return GestureDetector(
                  onTap: () => _showAchievementDetails(context, item, isUnlocked, unlocked[item.id]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUnlocked
                            ? AppColors.gold.withValues(alpha: 0.5)
                            : (isDark ? Colors.transparent : Colors.grey.shade300),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildShieldBadge(icon: item.icon, unlocked: isUnlocked, size: 48, iconSize: 22),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isUnlocked ? primaryTextColor : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
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
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) => oldDelegate.color != color;
}