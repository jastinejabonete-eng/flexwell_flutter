import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'knn_core.dart';

class KnnClassifier {
  KnnClassifier._();
  static final KnnClassifier instance = KnnClassifier._();

  Map<String, FlatKnnModel> _models = {};
  bool _loaded = false;

  /// The load currently in progress, so overlapping callers share one load
  /// instead of each parsing the JSON.
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  bool isReadyFor(String exercise) {
    final model = _models[exercise];
    return _loaded && model != null && model.count > 0;
  }

  Future<void> loadFromAssets() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/knn_training_data.json');
      _models = await compute(parseKnnModels, jsonString); // off the UI isolate
      _loaded = true;
      if (kDebugMode) verifyNormalization();
    } catch (e) {
      debugPrint('KNN training data failed to load: $e');
      rethrow;
    } finally {
      // On success _loaded short-circuits future calls; on failure this lets
      // the next caller retry.
      _loading = null;
    }
  }

  /// Main-isolate fallback; also what the worker's maths is checked against.
  /// Returns a real verdict, or [KnnVerdict.outOfDistribution] for a pose
  /// unlike anything in training, or [KnnVerdict.unavailable] if the model
  /// isn't loaded / input is unusable.
  KnnVerdict classifyDetailed(
    String exercise,
    List<double> rawFeatures, {
    int k = 5,
    int? minIncorrectVotes,
  }) {
    final model = _models[exercise];
    if (!_loaded || model == null) return const KnnVerdict.unavailable();
    return knnClassifyDetailed(model, rawFeatures,
        k: k, minIncorrectVotes: minIncorrectVotes);
  }

  /// Back-compat wrapper: bool? with OOD collapsed to null.
  bool? classify(
    String exercise,
    List<double> rawFeatures, {
    int k = 5,
    int? minIncorrectVotes,
  }) {
    final v = classifyDetailed(exercise, rawFeatures,
        k: k, minIncorrectVotes: minIncorrectVotes);
    return v.isOutOfDistribution ? null : v.isCorrect;
  }

  Map<String, Map<String, Object>> exportForWorker() =>
      _models.map((exercise, m) => MapEntry(exercise, m.toMessage()));

  /// Debug sanity check for the Python <-> Dart scaler sync. After z-scoring,
  /// each column of the stored training rows should print mean ~0 and
  /// std ~1. If not, the JSON was exported with the wrong mean/std (or the
  /// examples were already scaled in Python, so they are scaled twice).
  void verifyNormalization() {
    _models.forEach((exercise, m) {
      if (m.count == 0) {
        debugPrint('[KNN scaler] $exercise: no training examples');
        return;
      }
      for (var d = 0; d < m.dims; d++) {
        var sum = 0.0, sumSq = 0.0;
        for (var e = 0; e < m.count; e++) {
          final v = m.features[e * m.dims + d];
          sum += v;
          sumSq += v * v;
        }
        final mean = sum / m.count;
        final std = sqrt(max(0.0, sumSq / m.count - mean * mean));
        final ok = mean.abs() < 0.3 && std > 0.6 && std < 1.6;
        debugPrint('[KNN scaler] $exercise f$d: mean=${mean.toStringAsFixed(2)} '
            'std=${std.toStringAsFixed(2)} ${ok ? "ok" : "<-- CHECK EXPORT"}');
      }
    });
  }
}