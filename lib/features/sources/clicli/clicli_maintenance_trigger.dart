/// Daily coin maintenance trigger bound to app foreground events.
///
/// The maintenance itself is idempotent per calendar day, so the only job here
/// is to ask for a run often enough that a user who opens the app on any given
/// day collects that day's coins. Nothing runs in the background: if the app is
/// never opened, no coins are collected and no order is attempted.
library;

import 'package:flutter/widgets.dart';

import '../sources.dart';

/// Observes lifecycle changes and requests one maintenance pass per foreground
/// entry. Repeated resumes are cheap because the day is recorded after the
/// first successful run.
class CliCliMaintenanceTrigger with WidgetsBindingObserver {
  CliCliMaintenanceTrigger();

  bool _registered = false;

  /// Starts observing. Safe to call more than once.
  void attach() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;
    // The first foreground event may already have happened before attach.
    request();
  }

  void detach() {
    if (!_registered) return;
    WidgetsBinding.instance.removeObserver(this);
    _registered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) request();
  }

  /// Fire-and-forget: maintenance failures must never surface to the user or
  /// block the UI. [resumeMediaSourceMaintenance] already serializes runs and
  /// logs the outcome.
  void request() {
    resumeMediaSourceMaintenance();
  }
}
