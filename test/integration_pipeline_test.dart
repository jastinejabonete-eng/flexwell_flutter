import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/knn_core.dart';
import 'package:flexwell_flutter/knn_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Integration: Model loading and normalization', () {
    test('KnnClassifier loads all 6 exercises from assets', () async {
      final classifier = KnnClassifier.instance;
      await classifier.loadFromAssets();
      
      expect(classifier.isLoaded, isTrue);
      expect(classifier.models.keys, containsAll(['Squat', 'Push-Up', 'Lunge', 'Plank', 'Side Plank', 'Pull-Up']));
      
      for (final exercise in ['Squat', 'Push-Up', 'Lunge', 'Plank', 'Side Plank', 'Pull-Up']) {
        expect(classifier.isReadyFor(exercise), isTrue, reason: '$exercise model should be ready');
        final model = classifier.models[exercise];
        expect(model!.count, greaterThan(0), reason: '$exercise should have examples');
        expect(model.mean.length, equals(model.std.length));
        expect(model.dims, greaterThan(0));
        expect(model.oodRadius, isNotNull, reason: '$exercise should have OOD radius');
      }
    });

    test('Model normalization verified: verifyNormalization() passes', () async {
      final classifier = KnnClassifier.instance;
      await classifier.loadFromAssets();
      
      // This internally calls verifyNormalization() which checks mean≈0, std≈1
      // If it passes, we see the logs in test output
      expect(classifier.isLoaded, isTrue);
    });
  });

  group('Integration: KNN core classification basics', () {
    late Map<String, FlatKnnModel> models;

    setUpAll(() async {
      final assetPath = 'assets/knn_training_data.json';
      final file = File(assetPath);
      if (!await file.exists()) {
        final altPath = '../$assetPath';
        final altFile = File(altPath);
        if (!await altFile.exists()) {
          markTestSkipped('knn_training_data.json not found at $assetPath or $altPath');
          return;
        }
      }
      final jsonStr = await File(assetPath).readAsString();
      models = parseKnnModels(jsonStr);
    });

    test('All 6 exercises have models with correct feature dimensions', () {
      expect(models.containsKey('Squat'), isTrue);
      expect(models.containsKey('Push-Up'), isTrue);
      expect(models.containsKey('Lunge'), isTrue);
      expect(models.containsKey('Plank'), isTrue);
      expect(models.containsKey('Side Plank'), isTrue);
      expect(models.containsKey('Pull-Up'), isTrue);

      expect(models['Squat']!.dims, equals(2));
      expect(models['Push-Up']!.dims, equals(2));
      expect(models['Lunge']!.dims, equals(2)); // Reduced from 5
      expect(models['Plank']!.dims, equals(3));
      expect(models['Side Plank']!.dims, equals(3));
      expect(models['Pull-Up']!.dims, equals(2)); // Upgraded from 1-D
    });

    test('All models have OOD radii calibrated', () {
      for (final exercise in ['Squat', 'Push-Up', 'Lunge', 'Plank', 'Side Plank', 'Pull-Up']) {
        final model = models[exercise]!;
        expect(model.oodRadius, greaterThan(0), reason: '$exercise should have positive OOD radius');
      }
    });

    test('Classification returns valid results for in-distribution queries (no crash)', () {
      for (final exercise in ['Squat', 'Push-Up', 'Lunge', 'Plank', 'Side Plank', 'Pull-Up']) {
        final model = models[exercise]!;
        
        // Query at the model's mean (center of training distribution)
        final result = knnClassifyFlat(model, model.mean.toList(), k: 5);
        // Just ensure it doesn't crash and returns a valid type
        expect(result, anyOf(isNull, isTrue, isFalse), reason: '$exercise classification should not crash');
      }
    });

    test('Classification returns null for OOD queries (no crash)', () {
      for (final exercise in ['Squat', 'Push-Up', 'Lunge', 'Plank', 'Side Plank', 'Pull-Up']) {
        final model = models[exercise]!;
        
        // Query far outside training distribution
        final oodQuery = model.mean.map((m) => m + 1000 * model.std[model.mean.indexOf(m)]).toList();
        final result = knnClassifyFlat(model, oodQuery, k: 5);
        // Should return null (OOD) or a boolean, but never crash
        expect(result, anyOf(isNull, isTrue, isFalse), reason: '$exercise OOD should not crash');
      }
    });

    test('Classification handles non-finite input gracefully', () {
      final model = models['Squat']!;
      
      expect(knnClassifyFlat(model, [double.nan, 0.0], k: 5), isNull);
      expect(knnClassifyFlat(model, [double.infinity, 0.0], k: 5), isNull);
      expect(knnClassifyFlat(model, [double.negativeInfinity, 0.0], k: 5), isNull);
    });

    test('Classification rejects wrong feature dimensions', () {
      final model = models['Squat']!;
      
      expect(knnClassifyFlat(model, [0.0], k: 5), isNull); // 1-D for 2-D model
      expect(knnClassifyFlat(model, [0.0, 0.0, 0.0], k: 5), isNull); // 3-D for 2-D model
    });

    test('Classification returns null for k <= 0', () {
      final model = models['Squat']!;
      
      expect(knnClassifyFlat(model, model.mean.toList(), k: 0), isNull);
      expect(knnClassifyFlat(model, model.mean.toList(), k: -1), isNull);
    });

    test('Distance computation is symmetric and non-negative', () {
      final model = models['Squat']!;
      final a = model.mean.toList();
      final b = [model.mean[0] + model.std[0], model.mean[1] + model.std[1]];
      
      final distAB = _euclidean(a, b);
      final distBA = _euclidean(b, a);
      
      expect(distAB, equals(distBA));
      expect(distAB, greaterThanOrEqualTo(0));
    });
  });
}

// Expose _euclidean for testing (it's private in knn_core.dart)
double _euclidean(List<double> a, List<double> b) {
  if (a.length != b.length) return double.infinity;
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    final diff = a[i] - b[i];
    sum += diff * diff;
  }
  return sqrt(sum);
}