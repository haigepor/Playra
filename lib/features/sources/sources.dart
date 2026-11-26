/// Source bootstrap. Register new providers here; the rest of the app only
/// talks to [mediaSources] and never imports a concrete implementation.
library;

import 'dart:async';

import 'clicli/clicli_client.dart';
import 'clicli/clicli_config.dart';
import 'clicli/clicli_runtime.dart';
import 'clicli/clicli_source.dart';
import 'core/media_source.dart';

final MediaSourceRegistry mediaSources = MediaSourceRegistry();
CliCliClient? _cliCliClient;
Future<void>? _maintenanceRun;

/// One in-flight maintenance run per application process.
Future<void> resumeMediaSourceMaintenance() {
  final client = _cliCliClient;
  if (client == null) return Future<void>.value();
  final running = _maintenanceRun;
  if (running != null) return running;
  final future = runCliCliMaintenance(client).whenComplete(() {
    _maintenanceRun = null;
  });
  _maintenanceRun = future;
  return future;
}

/// Idempotent: safe to call from `main` and from tests.
MediaSourceRegistry bootstrapMediaSources() {
  if (mediaSources.maybeById(CliCliConfig.sourceId) != null) {
    return mediaSources;
  }
  final client = CliCliClient();
  _cliCliClient = client;
  mediaSources.register(CliCliSource(client: client));
  unawaited(resumeMediaSourceMaintenance());
  return mediaSources;
}
