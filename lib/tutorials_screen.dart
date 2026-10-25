import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'app_colors.dart';
import 'camera_screen.dart';
import 'fade_route.dart';
import 'exercise_camera_setup_dialog.dart';
import 'onboarding_tour_steps.dart';

class TutorialsScreen extends StatefulWidget {
  const TutorialsScreen({super.key});

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen> {
  int? _expandedIndex;

  // Local tutorial catalog bypassing the database
  final List<Map<String, String>> _localTutorials = [
    {
      'exercise': 'Squat',
      'title': 'LOWER BODY STRENGTH',
      'subtitle': 'Master the Squat Form',
      'imageAsset': 'assets/images/squat_bg.jpg',
      'videoAsset': 'assets/videos/squat_tutorial.mp4',
    },
    {
      'exercise': 'Push-Up',
      'title': 'UPPER BODY POWER',
      'subtitle': 'Perfect Your Push-Up',
      'imageAsset': 'assets/images/pushup_bg.jpg',
      // NOTE: was 'pushup_tutorixal.mp4'. Make sure this matches the real
      // file name in assets/videos/ and in pubspec.yaml.
      'videoAsset': 'assets/videos/pushup_tutorial.mp4',
    },
    {
      'exercise': 'Lunge',
      'title': 'BALANCE & CORE',
      'subtitle': 'Dynamic Lunge Execution',
      'imageAsset': 'assets/images/lunge_bg.jpg',
      'videoAsset': 'assets/videos/lunge_tutorial.mp4',
    },
    {
      'exercise': 'Pull-Up',
      'title': 'BACK & BICEPS',
      'subtitle': 'Pull-Up Mechanics',
      'imageAsset': 'assets/images/pullup_bg.jpg',
      'videoAsset': 'assets/videos/pullup_tutorial.mp4',
    },
    {
      'exercise': 'Plank',
      'title': 'CORE ENDURANCE',
      'subtitle': 'Static Plank Alignment',
      'imageAsset': 'assets/images/plank_bg.jpg',
      'videoAsset': 'assets/videos/plank_tutorial.mp4',
    },
    {
      'exercise': 'Side Plank',
      'title': 'ABDOMINAL FOCUS',
      'subtitle': 'Static Side-Planks',
      'imageAsset': 'assets/images/sideplank_bg.jpg',
      'videoAsset': 'assets/videos/sideplank_tutorial.mp4',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppColors.lightText;
    final cardBg = isDark ? AppColors.darkCardFilled : Colors.white;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final bannerHeight = (160 * textScale).clamp(160.0, 240.0);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Tutorials'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 90),
        itemCount: _localTutorials.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Learn the movement first',
                    key: OnboardingTourAnchors.tutorials,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: primaryTextColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Watch a demonstration, then start a scan with the right camera setup.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Six exercise tutorials',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSubtleFor(isDark),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '6 exercise guides',
                        style: TextStyle(
                          color: AppColors.accentFor(isDark),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final cardIndex = index - 1;
          final data = _localTutorials[cardIndex];
          final String exercise = data['exercise'] ?? '';
          final String title = data['title'] ?? '';
          final String subtitle = data['subtitle'] ?? '';
          final String imageAsset = data['imageAsset'] ?? '';
          final String videoAsset = data['videoAsset'] ?? '';

          final isExpanded = _expandedIndex == cardIndex;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isExpanded
                    ? AppColors.accentFor(isDark)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                width: isExpanded ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Exercise Banner Card
                SizedBox(
                  height: bannerHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: imageAsset.isNotEmpty
                            ? Image.asset(
                                imageAsset,
                                fit: BoxFit.cover,
                                // Missing/corrupt image: fall back to a flat colour.
                                errorBuilder: (_, _, _) =>
                                    Container(color: Colors.blueGrey.shade800),
                              )
                            : Container(color: Colors.blueGrey.shade800),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        bottom: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.brandSkyBlue,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 16,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.play_arrow_rounded,
                                color: isExpanded
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isExpanded
                                    ? 'Close tutorial'
                                    : 'Watch tutorial',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: isExpanded
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Semantics(
                          button: true,
                          expanded: isExpanded,
                          onTap: () {
                            setState(() {
                              _expandedIndex = isExpanded ? null : cardIndex;
                            });
                          },
                          label: isExpanded
                              ? 'Close $exercise tutorial video'
                              : 'Watch $exercise tutorial video',
                          child: ExcludeSemantics(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _expandedIndex = isExpanded
                                        ? null
                                        : cardIndex;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Expandable Local Asset Video Player Slot (~1/4 of screen height)
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: isExpanded
                      ? _AssetVideoPlayer(
                          // Key so a different card never reuses another card's controller.
                          key: ValueKey(videoAsset),
                          videoAsset: videoAsset,
                          exercise: exercise,
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Stateful helper widget to manage live video controller loading from local assets
class _AssetVideoPlayer extends StatefulWidget {
  final String videoAsset;
  final String exercise;

  const _AssetVideoPlayer({
    super.key,
    required this.videoAsset,
    required this.exercise,
  });

  @override
  State<_AssetVideoPlayer> createState() => _AssetVideoPlayerState();
}

class _AssetVideoPlayerState extends State<_AssetVideoPlayer> {
  // Nullable: stays null when the asset path is empty, so dispose() is safe.
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    if (widget.videoAsset.isEmpty) {
      _hasError = true; // safe: initState hasn't finished building yet
      return;
    }

    final controller = VideoPlayerController.asset(widget.videoAsset);
    _controller = controller;
    try {
      await controller.initialize();
      // The card may have been collapsed while the video was loading.
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Error loading video asset "${widget.videoAsset}": $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _scanButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: const Icon(Icons.camera_alt_rounded, size: 14),
      label: const Text(
        'SCAN NOW',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      onPressed: () async {
        if (_isInitialized) _controller?.pause();
        final shouldStart = await showExerciseCameraSetup(
          context,
          widget.exercise,
        );
        if (!mounted) return;
        if (shouldStart) {
          await Navigator.push(
            context,
            fadeRoute(CameraScreen(exercise: widget.exercise)),
          );
        }
        if (mounted && _isInitialized) {
          await _controller?.play();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    Widget child;
    if (_hasError) {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: Colors.white54,
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            'Video unavailable',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _scanButton(),
        ],
      );
    } else if (_isInitialized && controller != null) {
      child = Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: controller.value.isPlaying
                      ? 'Pause ${widget.exercise} video'
                      : 'Play ${widget.exercise} video',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    });
                  },
                ),
                _scanButton(),
              ],
            ),
          ),
        ],
      );
    } else {
      child = Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final videoHeight = widget.exercise == 'Pull-Up'
        ? screenHeight * 0.7
        : screenHeight * 0.25;

    return Container(
      width: double.infinity,
      height: videoHeight,
      color: Colors.black,
      child: child,
    );
  }
}
