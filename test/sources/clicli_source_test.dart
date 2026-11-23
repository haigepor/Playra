import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_client.dart';
import 'package:kazumi/features/sources/clicli/clicli_config.dart';
import 'package:kazumi/features/sources/clicli/clicli_source.dart';

class RecordingClient extends CliCliClient {
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> callData(
    String path,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    calls.add((path, payload));
    return {
      'videos': [],
      'pageinfo': {'pages': 1, 'pageIndex': 1},
    };
  }
}

void main() {
  for (final (sort, expected) in const [
    ('', ''),
    ('hot', 'hottest'),
    ('new', 'latest'),
    ('score', 'score'),
  ]) {
    test('browse sort "$sort" uses API value "$expected"', () async {
      final client = RecordingClient();
      final source = CliCliSource(client: client);
      await source.browse(categoryId: 'anime', sort: sort);
      expect(client.calls.single.$1, CliCliConfig.pathCategoryVideos);
      expect(client.calls.single.$2['sort'], expected);
      expect(client.calls.single.$2['categoryId'], 'anime');
    });
  }
}
