import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/source_models.dart';

void main() {
  test(
    'interrupted background channel is retried instead of being lost',
    () async {
      var attempts = 0;
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (operation == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '主频道'},
                  {'id': '2', 'name': '其他频道'},
                ],
              },
            };
          }
          if (operation == 'catalog' && payload['channelId'] == '2') {
            if (++attempts == 1) {
              throw const SourceException('CANCELLED', 'foreground request');
            }
          }
          return {
            'data': {'videos': [], 'banners': []},
          };
        },
      );
      final controller = LuminaHomeController(service);
      addTearDown(controller.dispose);
      addTearDown(service.dispose);
      await controller.bootstrap(warmOtherChannels: false);
      await controller.warmChannels();
      expect(attempts, 2);
      expect(controller.channelItems.containsKey('2'), isTrue);
    },
  );
}
