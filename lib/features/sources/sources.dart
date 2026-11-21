/// Source bootstrap. Register new providers here; the rest of the app only
/// talks to [mediaSources] and never imports a concrete implementation.
library;

import 'clicli/clicli_config.dart';
import 'clicli/clicli_source.dart';
import 'core/media_source.dart';

final MediaSourceRegistry mediaSources = MediaSourceRegistry();

/// Idempotent: safe to call from `main` and from tests.
MediaSourceRegistry bootstrapMediaSources() {
  if (mediaSources.maybeById(CliCliConfig.sourceId) != null) {
    return mediaSources;
  }
  mediaSources.register(CliCliSource());
  return mediaSources;
}
