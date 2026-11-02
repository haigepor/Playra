import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_engine/response_context.dart';

void main() {
  test(
    'play response context preserves id, format and exact encoded source episode',
    () {
      final uri = Uri.parse(
        'http://example.test/app/video/play?id=42&play=road3&part=%E7%AC%AC01%E9%9B%86',
      );
      expect(
        luminaResponsePath(uri),
        '/app/video/play?id=42&play=road3&part=%E7%AC%AC01%E9%9B%86',
      );
    },
  );
  test(
    'response context neither drops nor double-encodes special episode characters',
    () {
      final uri = Uri(
        scheme: 'http',
        host: 'example.test',
        path: '/app/video/play',
        queryParameters: {'id': '42', 'play': 'road3', 'part': 'OVA & 01/END'},
      );
      final context = luminaResponsePath(uri);
      expect(context, '/app/video/play?id=42&play=road3&part=OVA+%26+01%2FEND');
      expect(Uri.parse(context).queryParameters['part'], 'OVA & 01/END');
      expect(
        luminaResponsePath(Uri.parse('http://example.test/app/config')),
        '/app/config',
      );
    },
  );
}
