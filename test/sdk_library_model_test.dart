import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';

void main() {
  test('persisted milliseconds retain full precision on VM and Web', () {
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
    expect(watch.position.inMilliseconds, 754321);
    expect(watch.duration.inMilliseconds, 1415000);
    expect(watch.toJson()['positionMs'], 754321);
    expect(watch.completed, isFalse);
  });
}
