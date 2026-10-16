import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/sdk_playback_resume.dart';

void main() {
  test('async seek ignores transient zero, then permits explicit rewind', () {
    final guard = SdkResumeProgressGuard()
      ..waitFor(const Duration(milliseconds: 70400));
    expect(guard.accepts(Duration.zero), isFalse);
    expect(guard.accepts(const Duration(milliseconds: 667)), isFalse);
    expect(guard.accepts(const Duration(milliseconds: 70400)), isTrue);
    expect(guard.accepts(Duration.zero), isTrue);
    guard.waitFor(const Duration(seconds: 46));
    expect(guard.accepts(Duration.zero), isFalse);
    guard.waitFor(Duration.zero);
    expect(guard.accepts(Duration.zero), isTrue);
  });
  test(
    'quality changes restore exact subsecond position for the same episode length',
    () {
      expect(
        sdkResumePosition(
          position: const Duration(milliseconds: 45234),
          previousDuration: const Duration(seconds: 1415),
          targetDuration: const Duration(seconds: 1415),
        ),
        const Duration(milliseconds: 45234),
      );
    },
  );
  test('small source duration differences retain progress', () {
    expect(
      sdkResumePosition(
        position: const Duration(seconds: 45),
        previousDuration: const Duration(seconds: 1415),
        targetDuration: const Duration(seconds: 1418),
      ),
      const Duration(seconds: 45),
    );
  });
  test('different versions cannot inherit a misleading playback offset', () {
    expect(
      sdkResumePosition(
        position: const Duration(seconds: 45),
        previousDuration: const Duration(seconds: 1415),
        targetDuration: const Duration(seconds: 900),
      ),
      isNull,
    );
  });
  test('unknown, negative and out of range offsets are rejected', () {
    for (final position in [
      const Duration(seconds: -1),
      const Duration(seconds: 100),
    ]) {
      expect(
        sdkResumePosition(
          position: position,
          previousDuration: const Duration(seconds: 100),
          targetDuration: const Duration(seconds: 100),
        ),
        isNull,
      );
    }
    expect(
      sdkResumePosition(
        position: const Duration(seconds: 1),
        previousDuration: Duration.zero,
        targetDuration: const Duration(seconds: 100),
      ),
      isNull,
    );
  });
}
