import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'exercise_camera_guide.dart';

Future<bool> showExerciseCameraSetup(
  BuildContext context,
  String exercise,
) async {
  final guide = ExerciseCameraGuide.forExercise(exercise);
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.videocam_rounded,
            color: AppColors.primary,
            size: 34,
          ),
          title: Text('$exercise camera setup'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  avatar: const Icon(Icons.visibility_rounded, size: 18),
                  label: Text(guide.view),
                ),
                const SizedBox(height: 8),
                Text(guide.setup),
                if (guide.calibrates) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Hold your starting position still for about a second while FlexWell calibrates.',
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  guide.repBased
                      ? 'This scan counts repetitions.'
                      : 'This scan tracks your hold time.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue to camera'),
            ),
          ],
        ),
      ) ??
      false;
}
