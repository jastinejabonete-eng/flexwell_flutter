import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'knn_classifier.dart';
import 'knn_core.dart';

class KnnWorker {
  KnnWorker._();
  static final KnnWorker instance = KnnWorker._();

  /// After this many consecutive timeouts the worker is considered dead and
  /// classification falls back to the main isolate immediately.
  static const int _maxConsecutiveTimeouts = 3;

  Isolate? _isolate;
  ReceivePort? _replies;
  ReceivePort? _lifecycle; // receives onError / onExit from the isolate
  SendPort? _commands;
  Future<void>? _starting;
  int _users = 0;
  int _nextId = 0;
  int _timeouts = 0;

  /// Bumped on every shutdown. A _start() that began under an older
  /// generation knows it has been cancelled and cleans up after itself, so a
  /// release() -> acquire() overlap can't leak a second isolate.
  int _generation = 0;

  final Map<int, Completer<bool?>> _pending = {};

  /// Reference-counted so an overlapping screen transition can't kill the
  /// worker the new CameraScreen just started.
  Future<void> acquire() {
    _users++;
    final gen = _generation;
    return _starting ??= _start(gen).catchError((Object e, StackTrace st) {
      debugPrint('KnnWorker failed, using main-thread KNN: $e');
      // Only clear if nobody has restarted us in the meantime.
      if (gen == _generation) _starting = null;
    });
  }

  void release() {
    if (_users > 0) _users--;
    if (_users == 0) _shutdown();
  }

  Future<void> _start(int gen) async {
    await KnnClassifier.instance.loadFromAssets();
    if (gen != _generation) return; // cancelled while loading

    final replies = ReceivePort();
    final lifecycle = ReceivePort();
    final handshake = Completer<SendPort>();
    Isolate? isolate;

    void cleanup() {
      isolate?.kill(priority: Isolate.immediate);
      replies.close();
      lifecycle.close();
    }

    replies.listen((Object? msg) {
      if (msg is SendPort) {
        if (!handshake.isCompleted) handshake.complete(msg);
      } else if (msg is List) {
        final done = _pending.remove(msg[0] as int);
        final code = msg[1] as int;
        if (code >= 0) _timeouts = 0; // a real answer: worker is healthy
        done?.complete(code < 0 ? null : code == 1);
      }
    });

    // Fires if the worker throws an uncaught error or exits for any reason.
    lifecycle.listen((Object? _) => _onWorkerDied(gen));

    try {
      isolate = await Isolate.spawn(
        _workerMain,
        replies.sendPort,
        onError: lifecycle.sendPort,
        onExit: lifecycle.sendPort,
      );
      final commands =
          await handshake.future.timeout(const Duration(seconds: 3));

      if (gen != _generation) {
        // Released (and maybe re-acquired) while we were spawning.
        cleanup();
        return;
      }

      commands.send(<Object?>['init', KnnClassifier.instance.exportForWorker()]);
      _isolate = isolate;
      _replies = replies;
      _lifecycle = lifecycle;
      _commands = commands;
      _timeouts = 0;
    } catch (_) {
      cleanup();
      rethrow;
    }
  }

  /// Worker crashed or exited: stop sending it work, answer anything pending
  /// with "no verdict", and let classify() use the main isolate from now on.
  void _onWorkerDied(int gen) {
    if (gen != _generation) return; // expected exit from our own shutdown
    debugPrint('KnnWorker isolate died, falling back to main-thread KNN');
    _commands = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }

  /// Raw (un-normalized) features in; z-scoring happens inside the worker
  /// with the mean/std exported from Python's StandardScaler.
  Future<bool?> classify(
    String exercise,
    List<double> rawFeatures, {
    int k = 5,
    int? minIncorrectVotes,
  }) {
    bool? onMainIsolate() {
      try {
        return KnnClassifier.instance.classify(exercise, rawFeatures,
            k: k, minIncorrectVotes: minIncorrectVotes);
      } catch (e) {
        debugPrint('Main-thread KNN failed: $e');
        return null;
      }
    }

    final commands = _commands;
    if (commands == null) return Future.value(onMainIsolate());

    final id = _nextId++;
    final completer = Completer<bool?>();
    _pending[id] = completer;
    try {
      commands.send(
          <Object?>['classify', id, exercise, rawFeatures, k, minIncorrectVotes]);
    } catch (e) {
      _pending.remove(id);
      return Future.value(onMainIsolate());
    }

    // A stuck worker must never freeze the camera loop (_isBusy stays true
    // until analyze() returns).
    return completer.future.timeout(const Duration(milliseconds: 500),
        onTimeout: () {
      _pending.remove(id);
      _timeouts++;
      if (_timeouts >= _maxConsecutiveTimeouts) {
        debugPrint('KnnWorker unresponsive, disabling it '
            '(KNN now runs on the main isolate)');
        _commands = null;
      } else if (kDebugMode) {
        debugPrint('KnnWorker timeout $_timeouts/$_maxConsecutiveTimeouts '
            '(temporary main-isolate fallback)');
      }
      return onMainIsolate();
    });
  }

  void _shutdown() {
    _generation++; // cancels any in-flight _start()
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _lifecycle?.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _isolate = null;
    _replies = null;
    _lifecycle = null;
    _commands = null;
    _starting = null;
    _timeouts = 0;
  }
}

void _workerMain(SendPort toMain) {
  final commands = ReceivePort();
  final models = <String, FlatKnnModel>{};

  commands.listen((Object? msg) {
    // One bad message must never kill the isolate.
    int? id;
    try {
      final m = msg as List<Object?>;
      if (m[0] == 'init') {
        (m[1] as Map<Object?, Object?>).forEach((exercise, v) {
          try {
            models[exercise as String] =
                FlatKnnModel.fromMessage(v as Map<Object?, Object?>);
          } catch (_) {
            // Skip this exercise; the main isolate will handle it.
          }
        });
      } else if (m[0] == 'classify') {
        id = m[1] as int;
        final model = models[m[2] as String];
        final raw = List<double>.from(m[3] as List);
        final result = model == null
            ? null
            : knnClassifyFlat(model, raw,
                k: m[4] as int, minIncorrectVotes: m[5] as int?);
        toMain.send(<Object?>[id, result == null ? -1 : (result ? 1 : 0)]);
      }
    } catch (_) {
      if (id != null) toMain.send(<Object?>[id, -1]);
    }
  });

  toMain.send(commands.sendPort);
}