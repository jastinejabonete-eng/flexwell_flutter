import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_tour_steps.dart';

class OnboardingTourOverlay extends StatefulWidget {
  final GlobalKey overlayKey;
  final OnboardingTourStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isSaving;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const OnboardingTourOverlay({
    required this.overlayKey,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.isSaving,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    super.key,
  });

  @override
  State<OnboardingTourOverlay> createState() => _OnboardingTourOverlayState();
}

class _OnboardingTourOverlayState extends State<OnboardingTourOverlay> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _scheduleTargetMeasurement();
  }

  @override
  void didUpdateWidget(covariant OnboardingTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.targetKey != widget.step.targetKey) {
      _targetRect = null;
      _scheduleTargetMeasurement();
    }
  }

  void _scheduleTargetMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final overlayObject = widget.overlayKey.currentContext
          ?.findRenderObject();
      final targetObject = widget.step.targetKey.currentContext
          ?.findRenderObject();
      if (overlayObject is! RenderBox ||
          targetObject is! RenderBox ||
          !overlayObject.hasSize ||
          !targetObject.hasSize) {
        return;
      }

      final globalTopLeft = targetObject.localToGlobal(Offset.zero);
      final localTopLeft = overlayObject.globalToLocal(globalTopLeft);
      final measured = localTopLeft & targetObject.size;
      if (_targetRect != measured) setState(() => _targetRect = measured);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final target = _targetRect ?? _fallbackTarget(size);
        final bubbleWidth = math.min(size.width - 32, 400.0);
        final layoutDelegate = _TourCalloutLayoutDelegate(
          targetRect: target,
          bubbleWidth: bubbleWidth,
          maxBubbleHeight: size.height - 24,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _SpotlightPainter(
                targetRect: target,
                layoutDelegate: layoutDelegate,
              ),
            ),
            CustomSingleChildLayout(
              delegate: layoutDelegate,
              child: SizedBox(
                width: bubbleWidth,
                child: _TourCallout(
                  step: widget.step,
                  stepIndex: widget.stepIndex,
                  totalSteps: widget.totalSteps,
                  isSaving: widget.isSaving,
                  onPrevious: widget.onPrevious,
                  onNext: widget.onNext,
                  onSkip: widget.onSkip,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Rect _fallbackTarget(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    return Rect.fromCenter(center: center, width: 1, height: 1);
  }
}

class _TourCallout extends StatelessWidget {
  final OnboardingTourStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isSaving;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourCallout({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.isSaving,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'Step ${stepIndex + 1} of $totalSteps. ${step.title} '
          '${step.description}',
      child: Card(
        key: const ValueKey('tour_callout'),
        color: colorScheme.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(step.icon, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.title,
                      key: ValueKey('tour_title_$stepIndex'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${stepIndex + 1}/$totalSteps',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final previous = OutlinedButton(
                    key: const ValueKey('tour_back'),
                    onPressed: isSaving ? null : onPrevious,
                    child: const Text('Back'),
                  );
                  final skip = TextButton(
                    key: const ValueKey('tour_skip'),
                    onPressed: isSaving ? null : onSkip,
                    child: const Text('Skip'),
                  );
                  final next = FilledButton(
                    key: ValueKey(
                      stepIndex == totalSteps - 1 ? 'tour_finish' : 'tour_next',
                    ),
                    onPressed: isSaving ? null : onNext,
                    child: Text(stepIndex == totalSteps - 1 ? 'Done' : 'Next'),
                  );
                  if (constraints.maxWidth < 360 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Row(
                      children: [
                        if (stepIndex > 0)
                          IconButton(
                            key: const ValueKey('tour_back'),
                            tooltip: 'Back',
                            onPressed: isSaving ? null : onPrevious,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('tour_skip'),
                          tooltip: 'Skip tour',
                          onPressed: isSaving ? null : onSkip,
                          icon: const Icon(Icons.close_rounded),
                        ),
                        next,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [if (stepIndex > 0) previous, skip, next],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourCalloutLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect targetRect;
  final double bubbleWidth;
  final double maxBubbleHeight;
  Rect? bubbleRect;

  _TourCalloutLayoutDelegate({
    required this.targetRect,
    required this.bubbleWidth,
    required this.maxBubbleHeight,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.min(bubbleWidth, constraints.maxWidth),
      maxHeight: math.min(maxBubbleHeight, constraints.maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final availableAbove = targetRect.top - 20;
    final availableBelow = size.height - targetRect.bottom - 20;
    final placeBelow = availableBelow >= availableAbove;
    final maxTop = math.max(12.0, size.height - childSize.height - 12);
    final top = placeBelow
        ? (targetRect.bottom + 20).clamp(12.0, maxTop).toDouble()
        : (targetRect.top - childSize.height - 20)
              .clamp(12.0, maxTop)
              .toDouble();
    final left = ((size.width - childSize.width) / 2)
        .clamp(16.0, math.max(16.0, size.width - childSize.width - 16))
        .toDouble();
    bubbleRect = Rect.fromLTWH(left, top, childSize.width, childSize.height);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _TourCalloutLayoutDelegate oldDelegate) =>
      targetRect != oldDelegate.targetRect ||
      bubbleWidth != oldDelegate.bubbleWidth ||
      maxBubbleHeight != oldDelegate.maxBubbleHeight;
}

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final _TourCalloutLayoutDelegate layoutDelegate;

  const _SpotlightPainter({
    required this.targetRect,
    required this.layoutDelegate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final focus = targetRect.inflate(8);
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(focus, const Radius.circular(16)));
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.76),
    );

    final accent = Paint()
      ..color = const Color(0xFFC6FF00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(focus, const Radius.circular(16)),
      accent,
    );

    final bubbleRect = layoutDelegate.bubbleRect;
    if (bubbleRect == null) return;
    final targetBelowBubble = targetRect.center.dy > bubbleRect.center.dy;
    final start = Offset(
      bubbleRect.center.dx,
      targetBelowBubble ? bubbleRect.bottom : bubbleRect.top,
    );
    final end = Offset(
      targetRect.center.dx,
      targetBelowBubble ? focus.top - 4 : focus.bottom + 4,
    );
    final direction = (end - start).direction;
    final line = Paint()
      ..color = const Color(0xFFC6FF00)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, line);

    const arrowLength = 10.0;
    const arrowHalfWidth = 5.0;
    final arrowBase = end - Offset.fromDirection(direction, arrowLength);
    final side = Offset.fromDirection(direction + math.pi / 2, arrowHalfWidth);
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowBase.dx + side.dx, arrowBase.dy + side.dy)
      ..lineTo(arrowBase.dx - side.dx, arrowBase.dy - side.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFC6FF00));
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      targetRect != oldDelegate.targetRect ||
      layoutDelegate != oldDelegate.layoutDelegate;
}
