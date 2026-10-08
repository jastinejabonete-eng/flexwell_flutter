import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'achievement_service.dart';
import 'app_colors.dart';

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

  void _share(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    AchievementService.unlockAchievement('share');
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
        final cardBg = isDark ? const Color(0xFF1E232A) : Colors.white;
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
                    color: unlocked ? const Color(0xFFFFD700) : Colors.grey.shade400,
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
                          ? const Color(0xFFFFD700)
                          : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      foregroundColor: unlocked ? Colors.black : Colors.grey.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: unlocked ? 4 : 0,
                    ),
                    onPressed: unlocked
                        ? () {
                            _share(context, 'Sharing "${item.title}" achievement!');
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
    const goldColor = Color(0xFFFFD700);
    const slateColor = Color(0xFF94A3B8);

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
    final cardColor = isDark ? const Color(0xFF1E232A) : Colors.white;
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
            onPressed: () => _share(context, 'Sharing achievements overview...'),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
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
                            ? const Color(0xFFFFD700).withValues(alpha: 0.5)
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