import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Landmarks required by both the form analyzer and the on-screen skeleton.
class PoseLandmarkRequirements {
  static const _squat = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
  };
  static const _pushUp = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftAnkle,
  };
  static const _pullUp = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
  };
  static const _lunge = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
  };
  static const _plank = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftAnkle,
  };

  static Set<PoseLandmarkType> forExercise(String exercise) {
    switch (exercise) {
      case 'Squat':
        return _squat;
      case 'Push-Up':
        return _pushUp;
      case 'Pull-Up':
        return _pullUp;
      case 'Plank':
      case 'Side Plank':
        return _plank;
      default:
        return _lunge;
    }
  }
}
