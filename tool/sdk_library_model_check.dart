// ignore_for_file: avoid_print
import 'package:kazumi/services/storage/sdk_library_models.dart';

/// 可直接编译JS运行，保护VM测试无法覆盖的Web整数语义。
void main() {
  final watch = SdkWatchProgress.fromJson({
    'number': 99,
    'name': '第99集',
    'code': 'mp4',
    'reference': '第99集',
    'positionMs': 754321,
    'durationMs': 1415000,
    'updatedAt': 1792126000000,
    'automatic': false,
    'qualityCode': '2160p',
  });
  if (watch.position.inMilliseconds != 754321 ||
      watch.duration.inMilliseconds != 1415000 ||
      watch.episode.reference != '第99集' ||
      watch.automatic ||
      watch.completed) {
    throw StateError('SDK_LIBRARY_MODEL_MISMATCH');
  }
  print('SDK_LIBRARY_MODEL_PASS positionMs=754321 durationMs=1415000');
}
