class ExerciseCameraGuide {
  final String exercise;
  final String view;
  final String setup;
  final bool repBased;
  final bool calibrates;

  const ExerciseCameraGuide({
    required this.exercise,
    required this.view,
    required this.setup,
    required this.repBased,
    required this.calibrates,
  });

  static const all = [
    ExerciseCameraGuide(
      exercise: 'Squat',
      view: 'Left side view',
      setup:
          'Turn, so your left side faces the camera. Keep both shoulders and hips, along with your left knee and ankle, in view.',
      repBased: true,
      calibrates: true,
    ),
    ExerciseCameraGuide(
      exercise: 'Push-Up',
      view: 'Left side view',
      setup:
          'Turn, so your left side faces the camera. Keep your left shoulder, elbow, wrist, hip, and ankle visible.',
      repBased: true,
      calibrates: true,
    ),
    ExerciseCameraGuide(
      exercise: 'Pull-Up',
      view: 'Back view',
      setup:
          'Put the camera behind you, so both shoulders, elbows, and hips are visible.',
      repBased: true,
      calibrates: true,
    ),
    ExerciseCameraGuide(
      exercise: 'Lunge',
      view: 'Left side view',
      setup:
          'Turn, so your left side faces the camera. Keep your left shoulder, hip, knee, and ankle in frame.',
      repBased: true,
      calibrates: false,
    ),
    ExerciseCameraGuide(
      exercise: 'Plank',
      view: 'Left side view',
      setup:
          'Turn, so your left side faces the camera. Keep your shoulder, elbow, hip, and ankle visible, with a clear line from shoulder to ankle.',
      repBased: false,
      calibrates: false,
    ),
    ExerciseCameraGuide(
      exercise: 'Side Plank',
      view: 'Left side view',
      setup:
          'Turn, so your left side faces the camera. Keep your shoulder, elbow, hip, and ankle in view.',
      repBased: false,
      calibrates: false,
    ),
  ];

  static ExerciseCameraGuide forExercise(String exercise) =>
      all.firstWhere((guide) => guide.exercise == exercise);
}
