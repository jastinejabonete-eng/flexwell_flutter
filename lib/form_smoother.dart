import 'dart:collection';

/// Majority-vote smoother over the last [windowSize] per-frame verdicts.
/// Stops the skeleton flickering green/red for exercises that are classified
/// every frame (Lunge, Plank, Side Plank).
///
/// Until [minFrames] verdicts have been collected it passes the raw verdict
/// through, so feedback isn't delayed at the start of a session.
class FormSmoother {
  final int windowSize;
  final int minFrames;
  final Queue<bool> _window = Queue<bool>();
  int _correctCount = 0;

  // The camera loop processes ~10 frames/s (100 ms throttle), so 7 frames is
  // about 0.7 s. An odd window can't tie once it is full.
  FormSmoother({this.windowSize = 7, this.minFrames = 3});

  /// Adds one frame's verdict and returns the smoothed verdict.
  /// Ties count as correct, so borderline moments don't flash red.
  bool add(bool isCorrect) {
    _window.addLast(isCorrect);
    if (isCorrect) _correctCount++;
    if (_window.length > windowSize) {
      if (_window.removeFirst()) _correctCount--;
    }
    if (_window.length < minFrames) return isCorrect;
    final incorrectCount = _window.length - _correctCount;
    return _correctCount >= incorrectCount;
  }

  void reset() {
    _window.clear();
    _correctCount = 0;
  }
}