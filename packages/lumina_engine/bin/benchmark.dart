import 'dart:convert';
import 'dart:io';
import 'package:lumina_engine/lumina_engine.dart';
import 'package:lumina_engine/primitives.dart';

/// 同引擎、同 K、同密文；不包含 HTTP/RSA，冷标定与缓存命中分别统计。
void main(List<String> args) {
  if (args.length != 2) throw ArgumentError('image.bin report.json');
  final stages = <String, List<double>>{};
  final engine = LuminaEngine(
    args[0],
    trace: (stage, micros) {
      (stages[stage] ??= []).add(micros / 1000);
    },
  );
  final key = List.generate(16, (i) => i);
  final plain = List.generate(4096, (i) => i % 251);
  final cipher = engine.encrypt(key, pad(plain));
  double run() {
    final clock = Stopwatch()..start();
    final result = engine.decrypt(key, cipher);
    final ms = clock.elapsedMicroseconds / 1000;
    if (base64Encode(result) != base64Encode(plain)) {
      throw StateError('plaintext mismatch');
    }
    return ms;
  }

  run();
  stages.clear();
  final fresh = <double>[];
  for (var i = 0; i < 20; i++) {
    engine.clearCalibrationCache();
    fresh.add(run());
  }
  if (stages['calibration']?.length != 20) {
    throw StateError('fresh calibration count');
  }
  final calibrations = List<double>.from(stages['calibration']!);
  stages.clear();
  final hot = List.generate(20, (_) => run());
  if (stages.containsKey('calibration') ||
      stages['calibration_hit']?.length != 20) {
    throw StateError('same-K cache not used');
  }
  final short = List.generate(32, (i) => i);
  if (base64Encode(engine.decrypt(key, engine.encrypt(key, pad(short)))) !=
      base64Encode(short)) {
    throw StateError('calibration prefix mismatch');
  }
  for (var i = 1; i <= 9; i++) {
    final other = List.generate(16, (b) => (i * 17 + b) % 256);
    if (base64Encode(
          engine.decrypt(other, engine.encrypt(other, pad(short))),
        ) !=
        base64Encode(short)) {
      throw StateError('cross-key or eviction mismatch');
    }
  }
  final misses = stages['calibration']?.length ?? 0;
  run(); // 被 LRU 淘汰后必须仍能重算并得到同一明文。
  if (stages['calibration']?.length != misses + 1) {
    throw StateError('calibration key limit not enforced');
  }
  Map<String, double> percentiles(List<double> samples) {
    final sorted = samples.toList()..sort();
    return {'p50Ms': sorted[9], 'p95Ms': sorted[18]};
  }

  final report = {
    'platform': Platform.operatingSystem,
    'engine': engine.version,
    'cipherBytes': cipher.length,
    'samplesPerGroup': 20,
    'uncachedDecrypt': percentiles(fresh),
    'uncachedCalibration': percentiles(calibrations),
    'cachedDecrypt': percentiles(hot),
    'cachedCalibrationCalls': 0,
    'sameKeyPlaintextMatches': true,
    'prefixAndKeyEvictionPass': true,
  };
  final text = const JsonEncoder.withIndent('  ').convert(report);
  File(args[1]).writeAsStringSync(text);
  print(text);
}
