import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;

/// z = (x - mean) / std. The ONLY place normalization happens, for training
/// rows at load time and for live vectors at classify time.
/// std == 0 -> 1, same as sklearn's StandardScaler.
Float64List zScore(List<double> raw, Float64List mean, Float64List std) {
  final out = Float64List(raw.length);
  for (var i = 0; i < raw.length; i++) {
    out[i] = (raw[i] - mean[i]) / (std[i] == 0 ? 1.0 : std[i]);
  }
  return out;
}

/// Flat, isolate-friendly model: typed lists only, cheap to send to a worker.
class FlatKnnModel {
  final Float64List mean;
  final Float64List std;
  final int dims;
  final Float64List features; // count * dims, already z-scored
  final Uint8List isCorrect; // 1 = "correct"

  FlatKnnModel(this.mean, this.std, this.dims, this.features, this.isCorrect);

  int get count => isCorrect.length;

  factory FlatKnnModel.fromJson(Map<String, dynamic> value) {
    final meanList = value['mean'];
    final stdList = value['std'];
    final examples = value['examples'];
    if (meanList is! List || stdList is! List || examples is! List) {
      throw const FormatException('Model needs "mean", "std" and "examples" lists');
    }

    final mean = Float64List.fromList(
        [for (final v in meanList) (v as num).toDouble()]);
    final std = Float64List.fromList(
        [for (final v in stdList) (v as num).toDouble()]);
    final dims = mean.length;

    if (dims == 0) {
      throw const FormatException('Model has zero feature dimensions');
    }
    if (std.length != dims) {
      throw FormatException(
          'mean has $dims entries but std has ${std.length}');
    }
    if (mean.any((v) => !v.isFinite) || std.any((v) => !v.isFinite)) {
      throw const FormatException('mean/std contain non-finite values');
    }

    final features = Float64List(examples.length * dims);
    final isCorrect = Uint8List(examples.length);
    for (var e = 0; e < examples.length; e++) {
      final example = examples[e];
      if (example is! Map || example['features'] is! List) {
        throw FormatException('Example $e is malformed');
      }
      final raw = [
        for (final v in example['features'] as List) (v as num).toDouble()
      ];
      if (raw.length != dims) {
        throw FormatException('Example $e has ${raw.length} features, expected $dims');
      }
      if (raw.any((v) => !v.isFinite)) {
        throw FormatException('Example $e contains non-finite features');
      }
      features.setRange(e * dims, (e + 1) * dims, zScore(raw, mean, std));
      isCorrect[e] = example['label'] == 'correct' ? 1 : 0;
    }
    return FlatKnnModel(mean, std, dims, features, isCorrect);
  }

  Map<String, Object> toMessage() => {
        'mean': mean,
        'std': std,
        'dims': dims,
        'features': features,
        'isCorrect': isCorrect,
      };

  factory FlatKnnModel.fromMessage(Map<Object?, Object?> m) => FlatKnnModel(
        m['mean'] as Float64List,
        m['std'] as Float64List,
        m['dims'] as int,
        m['features'] as Float64List,
        m['isCorrect'] as Uint8List,
      );
}

/// Top-level so it can run inside compute() at startup.
/// A broken exercise entry is skipped (that exercise just has no model)
/// instead of failing the whole file.
Map<String, FlatKnnModel> parseKnnModels(String jsonString) {
  final data = json.decode(jsonString) as Map<String, dynamic>;
  final models = <String, FlatKnnModel>{};
  data.forEach((exercise, v) {
    try {
      models[exercise] = FlatKnnModel.fromJson(v as Map<String, dynamic>);
    } catch (e) {
      debugPrint('KNN model "$exercise" skipped: $e');
    }
  });
  return models;
}

/// Same behaviour as the old KnnClassifier.classify: true = correct,
/// false = incorrect, null = no verdict possible.
bool? knnClassifyFlat(
  FlatKnnModel m,
  List<double> raw, {
  int k = 5,
  int? minIncorrectVotes,
}) {
  if (k <= 0 || m.count == 0 || raw.length != m.dims) return null;
  // NaN / Infinity would poison every distance comparison.
  for (final v in raw) {
    if (!v.isFinite) return null;
  }

  final dims = m.dims;
  final q = zScore(raw, m.mean, m.std);
  final f = m.features;

  final bestDist = List<double>.filled(k, double.infinity);
  final bestCorrect = List<bool>.filled(k, false);
  var count = 0;

  for (var e = 0, base = 0; e < m.count; e++, base += dims) {
    var sum = 0.0;
    for (var i = 0; i < dims; i++) {
      final d = f[base + i] - q[i];
      sum += d * d;
    }
    if (count == k && sum >= bestDist[k - 1]) continue;
    var pos = count < k ? count : k - 1;
    while (pos > 0 && bestDist[pos - 1] > sum) {
      bestDist[pos] = bestDist[pos - 1];
      bestCorrect[pos] = bestCorrect[pos - 1];
      pos--;
    }
    bestDist[pos] = sum;
    bestCorrect[pos] = m.isCorrect[e] == 1;
    if (count < k) count++;
  }

  var correctVotes = 0;
  for (var i = 0; i < count; i++) {
    if (bestCorrect[i]) correctVotes++;
  }
  final incorrectVotes = count - correctVotes;
  if (minIncorrectVotes != null) return incorrectVotes < minIncorrectVotes;
  return correctVotes > count / 2;
}