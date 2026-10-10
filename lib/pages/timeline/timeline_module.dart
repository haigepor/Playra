import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/timeline/timeline_page.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/pages/calendar_page.dart';

final timelineModule = createModule(
  path: '/timeline',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => InterfacePageHost(
        legacy: (_) => TimelinePage(controller: inject<TimelineController>()),
        modern: (_) => const ModernCalendarPage(),
      ),
    );
  },
);
