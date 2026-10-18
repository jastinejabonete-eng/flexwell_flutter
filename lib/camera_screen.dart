import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pose_analyzer.dart';
import 'pose_painter.dart';
import 'summary_screen.dart';
import 'app_colors.dart';
import 'fade_route.dart';
import 'knn_classifier.dart';
import 'knn_worker.dart';
import 'form_smoother.dart';
import 'achievement_service.dart';

class CameraScreen extends StatefulWidget {
  final String exercise;
  const CameraScreen({super.key, required this.exercise});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  // Explicit stream mode + base model (the defaults). Do NOT switch to the
  // accurate model on low-end devices: it is much slower.
  final _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );
  final _poseAnalyzer = PoseAnalyzer();

  // Default to the BACK camera. A propped-up phone filming you (back camera)
  // is how the exercises are actually performed, and its feed is un-mirrored,
  // which is what the pose model was trained on. The front camera shows a
  // mirrored selfie preview, which looks inverted to the user.
  bool _isFrontCamera = false;
  bool get _mirrorFrontCameraPreview =>
      Platform.isAndroid && _isFrontCamera;
  bool _isBusy = false;
  bool _isStarting = false;
  bool _isSwitching = false;
  bool _isEnding = false;

  /// False until the KNN model finishes parsing. While false the preview runs
  /// but no verdict is issued -- the frame loop skips classification so the
  /// camera appears instantly instead of blocking on the 2.2MB model asset.
  bool _knnReady = false;
  bool _permissionGranted = false;
  bool _permissionPermanentlyDenied = false;
  String? _errorMessage;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // Everything that changes every processed frame (skeleton, verdict colour,
  // guide text) lives in this notifier. Updating it rebuilds only the skeleton
  // overlay and the guide bar, not the whole screen and camera preview.
  // `landmarksOk` is false when the analyzer can't judge form yet (landmarks
  // unreliable, calibrating, model missing): shown as neutral orange, not red.
  final ValueNotifier<_OverlayState> _overlay = ValueNotifier(_OverlayState.initial);
  int _repCount = 0;
  bool _isInDownPhase = false;
  DateTime? _holdStart;
  int _longestHold = 0;

  // ---------------------------------------------------------------------
  // Rep-phase thresholds — define when a rep is "down" vs "up"
  // for each exercise type.
  // ---------------------------------------------------------------------
  static const double _lungeDownThreshold = 100;
  static const double _lungeUpThreshold = 160;
  static const double _pullUpDownThreshold = -0.30;
  static const double _pullUpUpThreshold = -0.05;
  static const double _defaultDownThreshold = 0.30;
  static const double _defaultUpThreshold = 0.05;

  // ---------------------------------------------------------------------
  // Action-based accuracy (deadzone).
  // A frame only counts toward the accuracy score once the user has moved
  // meaningfully away from the resting/idle position.
  // ---------------------------------------------------------------------
  static const double _lungeEngageThreshold = 150; 
  static const double _pullUpEngageThreshold = -0.12; 
  static const double _defaultEngageThreshold = 0.12; 

  int _totalFrames = 0;
  int _correctFrames = 0;

  // ---------------------------------------------------------------------
  // Quality-tracked reps.
  // Tracks whether the rep currently in progress stayed correct throughout.
  // ---------------------------------------------------------------------
  bool _currentRepIsFlawless = true;
  int _perfectRepCount = 0;

  // ---------------------------------------------------------------------
  // Isometric hold debouncing (grace period).
  // ---------------------------------------------------------------------
  static const Duration _holdGracePeriod = Duration(milliseconds: 500);
  DateTime? _holdInterruptedAt;

  // Lower resolution = less data copied to ML Kit per frame. ML Kit resizes
  // its input internally anyway, so this mainly cuts cost on weak devices.
  static const ResolutionPreset _resolution = ResolutionPreset.low;
  List<CameraDescription>? _cachedCameras;

  // Adaptive frame skipping. The camera delivers ~30 fps; we analyse every
  // _processEveryNthFrame-th frame. If
  // ML Kit + KNN consistently overrun the frame budget, the busy gate drops
  // frames anyway, so raise the interval to rebuild the overlay at a rate the
  // device can actually sustain, and lower it again when processing is fast.
  int _processEveryNthFrame = _minFrameSkip; // starts at 2; re-adapts per device
  // Floor of 2 (was 3): at 30fps a skip of 3 costs ~100ms of latency, but the
  // adaptive logic below can still raise this up to _maxFrameSkip when the
  // device is over budget. Frame rate doesn't change what gets classified,
  // only how often, so a lower floor is free accuracy-wise.
  static const int _minFrameSkip = 2;
  static const int _maxFrameSkip = 8;
  // A processed frame should finish within this many ms to keep ~10 fps. An EMA
  // of the full process time decides the interval.
  static const double _frameBudgetMs = 120;
  double _avgProcessMs = _frameBudgetMs;
  int _skipCheckCountdown = _skipCheckEvery;
  static const int _skipCheckEvery = 15; // processed frames between adjustments
  int _frameCounter = 0;

  // Odd window: a full window can't tie. Incorrect is shown only when strictly
  // more than half of the last 5 frames were incorrect.
  final FormSmoother _displaySmoother = FormSmoother(windowSize: 5, minFrames: 3);
  int _missedFrames = 0;
  static const int _maxMissedFrames = 5;

  // Dropout hold: how many consecutive low-confidence frames to keep showing
  // the last good (smoothed) skeleton before blanking it. Stops the skeleton
  // blinking out for a single jittery frame while still clearing when tracking
  // is genuinely lost.
  static const int _poseHoldFrames = 3;
  int _unreliableStreak = 0;
  Pose? _lastGoodPose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  Future<void> _setup() async {
    _poseAnalyzer.resetCalibration();
    _permissionGranted = false;

    // Start the camera FIRST so the preview appears immediately, and load the
    // KNN model in parallel. The model parse (~1.8s for the 2.2MB asset) used
    // to block before the camera even started, which read as "ML Kit takes too
    // long to load". The preview now shows instantly and the first verdict just
    // arrives a beat later, once _knnReady flips.
    _knnReady = false;
    final knnFuture = _loadKnnModel();

    await KnnWorker.instance.acquire(); // never throws; falls back to main isolate

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _permissionPermanentlyDenied = status.isPermanentlyDenied;
        _errorMessage = 'Camera permission is required to analyze your posture.';
      });
      return;
    }
    _permissionGranted = true;
    await _startCamera();

    await knnFuture;
  }

  /// Loads the KNN model without blocking the camera preview. On failure the
  /// session reports the error and shows nothing but the "unavailable" state.
  Future<void> _loadKnnModel() async {
    try {
      await KnnClassifier.instance.loadFromAssets();
      if (!mounted) return;
      setState(() => _knnReady = true);
    } catch (e, st) {
      debugPrint('Failed to load KNN model: $e\n$st');
      _fail('Could not load the posture model. Please update or reinstall the app.');
    }
  }

  void _resetTracking() {
    _poseAnalyzer.resetCalibration();
    _displaySmoother.reset();
    _frameCounter = 0;
    _processEveryNthFrame = _minFrameSkip; // let it re-adapt for this device
    _avgProcessMs = _frameBudgetMs;
    _skipCheckCountdown = _skipCheckEvery;
    _missedFrames = 0;
    _unreliableStreak = 0;
    _lastGoodPose = null;
    _isInDownPhase = false;
    _holdStart = null;
    _holdInterruptedAt = null;
    _currentRepIsFlawless = true;
    if (mounted) _overlay.value = _OverlayState.initial;
  }

  Future<void> _releaseCamera() async {
    final old = _controller;
    if (old == null) return;
    if (mounted) {
      setState(() => _controller = null);
    } else {
      _controller = null;
    }
    try {
      if (old.value.isStreamingImages) await old.stopImageStream();
    } catch (_) {}
    try {
      await old.dispose();
    } catch (_) {}
  }

  Future<void> _startCamera() async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      final cameras = _cachedCameras ??= await availableCameras();
      if (cameras.isEmpty) {
        _cachedCameras = null;
        _fail('No camera was found on this device.');
        return;
      }
      final wanted = _isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => cameras.first,
      );
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      await _releaseCamera();
      _camera = camera;
      _resetTracking();

      final controller = CameraController(
        camera,
        _resolution,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted || _isEnding) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _errorMessage = null;
      });
      await controller.startImageStream(_processImage);
    } on CameraException catch (e) {
      debugPrint('Camera error: ${e.code} ${e.description}');
      _fail('Could not start the camera (${e.code}).');
    } catch (e, st) {
      debugPrint('Camera start failed: $e\n$st');
      _fail('Could not start the camera.');
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitching || _isStarting || _isEnding) return;
    _isSwitching = true;
    _isFrontCamera = !_isFrontCamera;
    try {
      await _startCamera();
    } finally {
      _isSwitching = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isEnding) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _permissionGranted &&
        _errorMessage == null &&
        !_isStarting) {
      _startCamera();
    }
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _permissionPermanentlyDenied = false;
    });
    _setup();
  }

  bool _isEngagedInMovement(String exercise, double repSignal) {
    if (exercise == 'Lunge') return repSignal <= _lungeEngageThreshold;
    if (exercise == 'Pull-Up') return repSignal <= _pullUpEngageThreshold;
    return repSignal >= _defaultEngageThreshold;
  }

  void _registerGoodHoldFrame() {
    _holdInterruptedAt = null;
    _holdStart ??= DateTime.now();
    final elapsed = DateTime.now().difference(_holdStart!).inSeconds;
    if (elapsed > _longestHold) _longestHold = elapsed;
  }

  void _registerHoldInterruption() {
    if (_holdStart == null) return;
    _holdInterruptedAt ??= DateTime.now();
    if (DateTime.now().difference(_holdInterruptedAt!) > _holdGracePeriod) {
      _holdStart = null;
      _holdInterruptedAt = null;
    }
  }

  void _processImage(CameraImage image) async {
    if (_isBusy || _isEnding || !mounted) return;
    if (++_frameCounter % _processEveryNthFrame != 0) return; // frame skipper
    _isBusy = true;
    // Total process time is measured in both debug and release so the adaptive
    // frame-skip logic works on real devices, not just debug builds.
    final sw = Stopwatch()..start();

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final rotation = inputImage.metadata!.rotation;
      final rotatedIsSideways =
          rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;
      final displaySize = rotatedIsSideways
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      final poses = await _poseDetector.processImage(inputImage);
      final mlMs = sw.elapsedMilliseconds;
      if (!mounted || _isEnding) return;

      if (poses.isNotEmpty) {
        // Hold the form verdict until the KNN model has finished parsing --
        // otherwise the first frames classify against a half-loaded model. The
        // preview is already live by now, so this is at most a ~2s wait before
        // the first verdict instead of a ~2s wait before the camera appears.
        if (!_knnReady) return;
        final pose = poses.first;
        // Start-position gate: if the user clearly isn't in this exercise's
        // required starting position (wrong side, standing when they should be
        // prone, not hanging, etc.), show an orange skeleton with the reason
        // instead of a misleading green/red form verdict. Run this before
        // analysis so an invalid starting pose cannot be used for calibration.
        final notReady = PoseAnalyzer.checkStartPosition(widget.exercise, pose);
        if (notReady != null) {
          final previous = _overlay.value;
          _overlay.value = _OverlayState(
            pose: pose,
            imageSize: displaySize,
            isCorrect: previous.isCorrect,
            landmarksOk: true, // keep drawing the skeleton...
            showNeutral: true, // ...but orange, with the position message
            guideText: notReady,
          );
          return; // finally block resets _isBusy and updates the frame skip
        }

        final analysis = await _poseAnalyzer.analyze(widget.exercise, pose);
        if (!mounted || _isEnding) return; // state may have changed during the await

        if (kDebugMode) {
          debugPrint('[perf] mlkit=${mlMs}ms total=${sw.elapsedMilliseconds}ms');
        }

        if (analysis.landmarksReliable) {
          if (PoseAnalyzer.repBasedExercises.contains(widget.exercise)) {
            final engaged = _isEngagedInMovement(widget.exercise, analysis.repSignal);

            if (engaged) {
              _totalFrames++;
              if (analysis.isCorrect) _correctFrames++;
            }

            if (_isInDownPhase && engaged && !analysis.isCorrect) {
              _currentRepIsFlawless = false;
            }

            if (widget.exercise == 'Lunge') {
              if (analysis.repSignal <= _lungeDownThreshold) {
                if (!_isInDownPhase) _currentRepIsFlawless = true;
                _isInDownPhase = true;
              } else if (analysis.repSignal >= _lungeUpThreshold && _isInDownPhase) {
                _repCount++;
                if (_currentRepIsFlawless) _perfectRepCount++;
                _isInDownPhase = false;
              }
            } else if (widget.exercise == 'Pull-Up') {
              if (analysis.repSignal <= _pullUpDownThreshold) {
                if (!_isInDownPhase) _currentRepIsFlawless = true;
                _isInDownPhase = true;
              } else if (analysis.repSignal >= _pullUpUpThreshold && _isInDownPhase) {
                _repCount++;
                if (_currentRepIsFlawless) _perfectRepCount++;
                _isInDownPhase = false;
              }
            } else {
              if (analysis.repSignal >= _defaultDownThreshold) {
                if (!_isInDownPhase) _currentRepIsFlawless = true;
                _isInDownPhase = true;
              } else if (analysis.repSignal <= _defaultUpThreshold && _isInDownPhase) {
                _repCount++;
                if (_currentRepIsFlawless) _perfectRepCount++;
                _isInDownPhase = false;
              }
            }
          } else {
            _totalFrames++;
            if (analysis.isCorrect) {
              _correctFrames++;
              _registerGoodHoldFrame();
            } else {
              _registerHoldInterruption();
            }
          }
        } else {
          _registerHoldInterruption();
        }

        _missedFrames = 0;
        final previous = _overlay.value;
        var isCorrect = previous.isCorrect;
        // Only reliable frames feed the verdict; unreliable ones must not
        // count as "incorrect form".
        if (analysis.landmarksReliable) {
          isCorrect = PoseAnalyzer.frontBackExercises.contains(widget.exercise)
              ? _displaySmoother.add(analysis.isCorrect)
              : analysis.isCorrect; // Lunge/Plank are already smoothed in the analyzer
        }
        // Sticky reliability: once the skeleton is showing, keep showing it even
        // if confidence momentarily dips. Only drop out when it stays below the
        // clear-cutoff for a few frames in a row (see _missedFrames logic below).
        if (analysis.landmarksReliable) {
          _unreliableStreak = 0;
          _lastGoodPose = analysis.smoothedPose ?? pose;
        } else {
          _unreliableStreak++;
        }
        final holdGoodPose =
            !analysis.landmarksReliable && _unreliableStreak < _poseHoldFrames;
        final drawPose = analysis.landmarksReliable
            ? (analysis.smoothedPose ?? pose)
            : (holdGoodPose ? _lastGoodPose : null);
        // Always show the analyzer's message (correction / calibrating /
        // "can't see you"), so stale text never stays on screen.
        _overlay.value = _OverlayState(
          pose: drawPose,
          imageSize: displaySize,
          isCorrect: isCorrect,
          landmarksOk: analysis.landmarksReliable || holdGoodPose,
          guideText: analysis.message,
        );
      } else {
        _registerHoldInterruption();
        _missedFrames++;
        // Person fully out of frame: no reliable pose to hold, so clear the
        // hold state (a re-entry needs a fresh good pose, not a stale one).
        _unreliableStreak = _poseHoldFrames;
        _lastGoodPose = null;
        if (_missedFrames >= _maxMissedFrames) {
          final previous = _overlay.value;
          _overlay.value = _OverlayState(
            pose: null,
            imageSize: previous.imageSize,
            isCorrect: previous.isCorrect,
            landmarksOk: previous.landmarksOk,
            guideText: 'No person detected -- step into frame',
          );
        }
      }
    } catch (e, st) {
      debugPrint('Error processing image: $e\n$st');
    } finally {
      _isBusy = false;
      _updateFrameSkip(sw.elapsedMilliseconds.toDouble());
    }
  }

  /// Feed the just-measured process time into an EMA and, every
  /// [_skipCheckEvery] processed frames, raise the skip interval while the
  /// device is over budget and lower it again when it has headroom. Smoothing
  /// over many frames keeps a single ML Kit hiccup from stutter-stepping the
  /// analysis rate.
  void _updateFrameSkip(double elapsedMs) {
    _avgProcessMs = 0.8 * _avgProcessMs + 0.2 * elapsedMs;
    if (--_skipCheckCountdown > 0) return;
    _skipCheckCountdown = _skipCheckEvery;

    final int previous = _processEveryNthFrame;
    if (_avgProcessMs > _frameBudgetMs) {
      // Over budget: analyse fewer frames so the overlay update keeps up.
      if (_processEveryNthFrame < _maxFrameSkip) _processEveryNthFrame++;
    } else if (_avgProcessMs < _frameBudgetMs * 0.6) {
      // Comfortable headroom: restore responsiveness.
      if (_processEveryNthFrame > _minFrameSkip) _processEveryNthFrame--;
    }
    if (_processEveryNthFrame != previous) {
      _frameCounter = 0; // realign the modulo window to the new interval
      if (kDebugMode) {
        debugPrint('[perf] frame skip $previous->$_processEveryNthFrame '
            '(avg ${_avgProcessMs.toStringAsFixed(0)}ms)');
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _endSession() async {
    if (_isEnding) return;
    _isEnding = true;

    final controller = _controller;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    // Judge any rep still in progress so stopping mid-rep (or at the bottom of
    // a squat) is still scored instead of silently dropped.
    try {
      await _poseAnalyzer.finalizeRep(widget.exercise);
    } catch (_) {}

    final accuracy = _totalFrames > 0 ? (_correctFrames * 100 / _totalFrames).round() : 0;

    // Save the session and evaluate achievements. Awaiting here (rather than
    // fire-and-forget) gives us the list of newly-unlocked badge ids to hand
    // to the SummaryScreen, which shows the celebration once it is on screen
    // (the CameraScreen is being replaced, so it can't show the dialog itself).
    final unlocked = await AchievementService.recordSession(
      exercise: widget.exercise,
      accuracy: accuracy,
      reps: _repCount,
      longestHold: _longestHold,
      reliableFrames: _totalFrames,
      perfectReps: _perfectRepCount,
    );

    if (!mounted) return;

    await Navigator.pushReplacement(
      context,
      fadeRoute(
        SummaryScreen(
          exercise: widget.exercise,
          accuracy: accuracy,
          reps: _repCount,
          longestHold: _longestHold,
          isRepBased: PoseAnalyzer.repBasedExercises.contains(widget.exercise),
          perfectReps: _perfectRepCount,
          unlockedAchievements: unlocked,
        ),
      ),
    );
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _poseDetector.close();
    _overlay.dispose();
    KnnWorker.instance.release();
    super.dispose();
  }

  Widget _buildErrorScaffold() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 56),
                const SizedBox(height: 20),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                if (_permissionPermanentlyDenied)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: openAppSettings,
                    child: const Text('OPEN SETTINGS'),
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _retry,
                    child: const Text('TRY AGAIN'),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Go back', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) return _buildErrorScaffold();

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final screenSize = constraints.biggest;
              final previewAspectRatio = 1 / controller.value.aspectRatio;

              var scale = screenSize.aspectRatio / previewAspectRatio;
              if (scale < 1) scale = 1 / scale;

              final Widget preview = Center(
                child: AspectRatio(
                  aspectRatio: previewAspectRatio,
                  child: CameraPreview(controller),
                ),
              );
              final alignedPreview = Transform.scale(
                scaleX: _mirrorFrontCameraPreview ? -1 : 1,
                child: preview,
              );

              // RepaintBoundary keeps the preview on its own layer so the
              // skeleton repainting never forces the preview to repaint.
              return RepaintBoundary(
                child: ClipRect(
                  child: Transform.scale(
                    scale: scale,
                    child: alignedPreview,
                  ),
                ),
              );
            },
          ),
          RepaintBoundary(
            child: ValueListenableBuilder<_OverlayState>(
              valueListenable: _overlay,
              builder: (context, o, _) => CustomPaint(
                painter: PosePainter(
                  // Draw the skeleton whenever we have a good pose. It turns
                  // orange (isNeutral) while calibrating / unreliable / not in
                  // the start position, so the user always sees their body.
                  pose: o.landmarksOk ? o.pose : null,
                  isCorrect: o.isCorrect,
                  isNeutral: !o.landmarksOk || o.showNeutral,
                  imageSize: o.imageSize,
                  // Must match the preview's aspect ratio exactly, or the
                  // skeleton is scaled into the wrong box and drifts off-body.
                  previewAspectRatio: controller.value.aspectRatio,
                  isFrontCamera: _mirrorFrontCameraPreview,
                  hideLowerBody: PosePainter.hidesLowerBody(widget.exercise),
                  requiredLandmarks: PosePainter.requiredFor(widget.exercise),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _glassContainer(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              widget.exercise,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _circularButton(
                            icon: Icons.cameraswitch_rounded,
                            tooltip: 'Switch camera',
                            onPressed: _switchCamera,
                          ),
                          const SizedBox(width: 8),
                          _circularButton(
                            icon: Icons.stop_rounded,
                            tooltip: 'End workout',
                            color: AppColors.incorrect,
                            onPressed: _endSession,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  ValueListenableBuilder<_OverlayState>(
                    valueListenable: _overlay,
                    builder: (context, o, _) => _glassContainer(
                      width: double.infinity,
                      backgroundColor: o.pose == null
                          ? Colors.black.withValues(alpha: 0.65)
                          : (!o.landmarksOk || o.showNeutral
                              ? Colors.orange.shade800.withValues(alpha: 0.85)
                              : o.isCorrect
                              ? AppColors.correct.withValues(alpha: 0.85)
                              : AppColors.incorrect.withValues(alpha: 0.85)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            o.pose == null
                                ? Icons.person_search_rounded
                                : (!o.landmarksOk || o.showNeutral
                                    ? Icons.info_outline_rounded
                                    : (o.isCorrect ? Icons.check_circle_rounded : Icons.warning_rounded)),
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              o.guideText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _glassContainer({required Widget child, double? width, Color? backgroundColor}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: child,
    );
  }

  Widget _circularButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color color = AppColors.primary,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}

/// Immutable snapshot of everything drawn on top of the camera preview.
class _OverlayState {
  final Pose? pose;
  final Size imageSize;
  final bool isCorrect;
  final bool landmarksOk;
  final String guideText;

  /// True when the skeleton should be drawn orange to signal "can't judge form
  /// yet / not in position" rather than red (incorrect) or green (correct).
  /// Distinct from landmarksOk so the skeleton still draws while orange.
  final bool showNeutral;

  const _OverlayState({
    required this.pose,
    required this.imageSize,
    required this.isCorrect,
    required this.landmarksOk,
    required this.guideText,
    this.showNeutral = false,
  });

  static const initial = _OverlayState(
    pose: null,
    imageSize: Size(1, 1),
    isCorrect: true,
    landmarksOk: true,
    guideText: 'Position yourself in frame',
  );

  /// Rebuilds the overlay only when something the user can actually SEE
  /// changed. A new Pose arrives on every processed frame, so without this
  /// the overlay would rebuild ~90 times a second even while the user stands
  /// still -- wasted rebuilds, and (worse) it makes the ValueNotifier's
  /// identity-based equality do all the work, which is fragile: any future
  /// change that starts comparing by value would freeze the skeleton.
  ///
  /// `pose` is compared by reference on purpose: PoseAnalyzer hands over a new
  /// Pose object every frame, so reference equality means "a new frame
  /// arrived" -- exactly what should trigger a repaint. `imageSize` and
  /// `showNeutral` are included so a camera switch or a neutral-state flip
  /// repaints even when the pose reference happens to match.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _OverlayState &&
          runtimeType == other.runtimeType &&
          pose == other.pose &&
          isCorrect == other.isCorrect &&
          landmarksOk == other.landmarksOk &&
          guideText == other.guideText &&
          showNeutral == other.showNeutral &&
          imageSize == other.imageSize;

  @override
  int get hashCode =>
      Object.hash(pose, isCorrect, landmarksOk, guideText, showNeutral, imageSize);
}