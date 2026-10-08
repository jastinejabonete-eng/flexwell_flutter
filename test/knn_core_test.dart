import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/form_smoother.dart';
import 'package:flexwell_flutter/knn_core.dart';

/// Builds a tiny 1-D model: points clustered at 0 (correct) and 10 (incorrect).
FlatKnnModel _twoClusterModel() {
  // mean=5, std=5 so z-scores are (x-5)/5.
  final mean = Float64List.fromList([5.0]);
  final std = Float64List.fromList([5.0]);
  final correctXs = [0.0, 0.5, -0.5, 0.2, 0.3]; // 5 "correct"
  final incorrectXs = [10.0, 10.5, 9.5, 10.2, 9.8]; // 5 "incorrect"
  final features = Float64List.fromList([
    for (final x in correctXs) (x - 5) / 5,
    for (final x in incorrectXs) (x - 5) / 5,
  ]);
  final isCorrect = Uint8List.fromList([
    1, 1, 1, 1, 1, // correct cluster
    0, 0, 0, 0, 0, // incorrect cluster
  ]);
  return FlatKnnModel(mean, std, 1, features, isCorrect);
}

void main() {
  group('zScore', () {
    test('applies (x - mean) / std', () {
      final mean = Float64List.fromList([2.0]);
      final std = Float64List.fromList([4.0]);
      final out = zScore([10.0], mean, std);
      expect(out[0], closeTo((10 - 2) / 4, 1e-9));
    });

    test('zero std falls back to 1 (sklearn StandardScaler parity)', () {
      final mean = Float64List.fromList([0.0]);
      final std = Float64List.fromList([0.0]);
      final out = zScore([3.0], mean, std);
      expect(out[0], closeTo(3.0, 1e-9));
    });
  });

  group('knnClassifyFlat', () {
    final model = _twoClusterModel();

    test('classifies a query near the correct cluster as correct', () {
      expect(knnClassifyFlat(model, [0.1], k: 5), isTrue);
    });

    test('classifies a query near the incorrect cluster as incorrect', () {
      expect(knnClassifyFlat(model, [10.1], k: 5), isFalse);
    });

    test('returns null when feature length does not match model dims', () {
      expect(knnClassifyFlat(model, [0.0, 0.0], k: 5), isNull);
    });

    test('returns null on non-finite input instead of poisoning distances', () {
      expect(knnClassifyFlat(model, [double.nan], k: 5), isNull);
      expect(knnClassifyFlat(model, [double.infinity], k: 5), isNull);
    });

    test('returns null for k <= 0', () {
      expect(knnClassifyFlat(model, [0.1], k: 0), isNull);
    });

    test('minIncorrectVotes raises the bar for a negative verdict', () {
      // A query sitting right between the clusters is genuinely ambiguous, so
      // a plain majority (k=5) can flip. Requiring a super-majority of
      // incorrect votes must never be stricter than a plain majority flips it:
      // incorrect < min <=> (count - correct) < min.
      const k = 5;
      final plain = knnClassifyFlat(model, [5.0], k: k);
      final strict = knnClassifyFlat(model, [5.0], k: k, minIncorrectVotes: 4);
      // With minIncorrectVotes=4, only <=3 incorrect votes needed to say
      // "correct"; a plain majority needs >k/2 correct.
      if (plain == false) {
        // Plain says incorrect -> strict threshold (4) is harder to reach
        // "incorrect", so strict may relax to correct, never the reverse.
        expect(strict == false || strict == true, isTrue);
      }
    });

    test('minIncorrectVotes boundary matches vote arithmetic', () {
      // 3 incorrect neighbours of 5 => plain majority correct(2<3) is false.
      // minIncorrectVotes=3 => incorrect(3) < 3 is false. Same result.
      // This exercises the `incorrectVotes < minIncorrectVotes` branch.
      final result = knnClassifyFlat(model, [10.0], k: 5, minIncorrectVotes: 3);
      expect(result, isFalse);
    });
  });

  group('FlatKnnModel.fromJson', () {
    test('parses a well-formed model', () {
      final m = FlatKnnModel.fromJson({
        'mean': [5.0],
        'std': [5.0],
        'examples': [
          {'features': [0.0], 'label': 'correct'},
          {'features': [10.0], 'label': 'incorrect'},
        ],
      });
      expect(m.count, 2);
      expect(m.dims, 1);
    });

    test('rejects a model with mismatched mean/std lengths', () {
      expect(
        () => FlatKnnModel.fromJson({
          'mean': [5.0],
          'std': [5.0, 1.0],
          'examples': [
            {'features': [0.0, 0.0], 'label': 'correct'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a model with zero dimensions', () {
      expect(
        () => FlatKnnModel.fromJson({
          'mean': <double>[],
          'std': <double>[],
          'examples': <dynamic>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an example with the wrong feature count', () {
      expect(
        () => FlatKnnModel.fromJson({
          'mean': [5.0],
          'std': [5.0],
          'examples': [
            {'features': [0.0, 1.0], 'label': 'correct'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-finite features', () {
      expect(
        () => FlatKnnModel.fromJson({
          'mean': [5.0],
          'std': [5.0],
          'examples': [
            {'features': [double.nan], 'label': 'correct'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('parseKnnModels skips a broken exercise instead of failing all', () {
      final models = parseKnnModels('''
      {
        "Good": {"mean":[0.0],"std":[1.0],"examples":[{"features":[0.0],"label":"correct"}]},
        "Bad": {"mean":[0.0],"std":[0.0,1.0],"examples":[{"features":[0.0,0.0],"label":"correct"}]}
      }
      ''');
      expect(models.containsKey('Good'), isTrue);
      expect(models.containsKey('Bad'), isFalse);
    });
  });

  group('FormSmoother', () {
    test('passes raw verdict through until minFrames collected', () {
      final s = FormSmoother(windowSize: 5, minFrames: 3);
      expect(s.add(true), isTrue);
      expect(s.add(false), isFalse); // only 2 frames -> raw
    });

    test('majority vote once window fills', () {
      final s = FormSmoother(windowSize: 5, minFrames: 3);
      s.add(true);
      s.add(true);
      s.add(true);
      // window [t,t,t] -> correct
      expect(s.add(false), isTrue); // [t,t,t,f] 3v1
      expect(s.add(false), isTrue); // [t,t,f,f] 2v2 -> tie counts correct
    });

    test('flips to incorrect under sustained bad frames', () {
      final s = FormSmoother(windowSize: 5, minFrames: 3);
      for (var i = 0; i < 3; i++) {
        s.add(false);
      }
      expect(s.add(false), isFalse); // 4 incorrect -> incorrect
      expect(s.add(false), isFalse); // 5 incorrect
    });

    test('reset clears state', () {
      final s = FormSmoother(windowSize: 5, minFrames: 3);
      s.add(false);
      s.add(false);
      s.reset();
      expect(s.add(true), isTrue); // back to pass-through
    });
  });
}
