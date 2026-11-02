import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/player/sdk_playback_notice.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets('compact notice supports recovery at 320px and scale $scale', (
      tester,
    ) async {
      var retries = 0, switches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SdkPlaybackNotice(
                    message: '播放响应解析失败，请重试或切换线路。',
                    onRetry: () => retries++,
                    onSwitch: () => switches++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      if (scale == 1)
        expect(
          tester
              .getSize(find.byKey(const ValueKey('sdk-playback-notice')))
              .height,
          lessThan(100),
        );
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      await tester.tap(find.byTooltip('更多恢复操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换线路'));
      await tester.pumpAndSettle();
      expect(switches, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
