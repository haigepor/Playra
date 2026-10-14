import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/pages/player/player_buffering_overlay.dart';

class FeedbackStreams implements PlayerStream {
  final bufferingEvents = StreamController<bool>.broadcast();
  final percentageEvents = StreamController<double>.broadcast();
  @override
  Stream<bool> get buffering => bufferingEvents.stream;
  @override
  Stream<double> get bufferingPercentage => percentageEvents.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  Future<void> close() async {
    await bufferingEvents.close();
    await percentageEvents.close();
  }
}

class FeedbackPlayer implements Player {
  @override
  final FeedbackStreams stream = FeedbackStreams();
  @override
  PlayerState state = const PlayerState(buffering: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget surface(Player? player, {bool resolving = false}) => MaterialApp(
  home: Scaffold(
    body: PlayerBufferingOverlay(
      player: player,
      buffering: false,
      resolving: resolving,
    ),
  ),
);

void main() {
  testWidgets('seek buffering updates without the position polling timer', (
    tester,
  ) async {
    final player = FeedbackPlayer();
    addTearDown(player.stream.close);
    await tester.pumpWidget(surface(player));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    player.stream.bufferingEvents.add(true);
    await tester.pump();
    expect(find.text('正在缓冲'), findsOneWidget);
    player.stream.percentageEvents.add(37.5);
    await tester.pump();
    expect(find.text('缓冲 38%'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(0.375, 0.001),
    );
    player.stream.bufferingEvents.add(false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a later seek clears the previous percentage, including 100%', (
    tester,
  ) async {
    final player = FeedbackPlayer();
    addTearDown(player.stream.close);
    await tester.pumpWidget(surface(player));
    player.stream.bufferingEvents.add(true);
    player.stream.percentageEvents.add(100);
    await tester.pump();
    expect(find.text('缓冲 100%'), findsOneWidget);
    player.stream.bufferingEvents.add(false);
    await tester.pump();
    player.stream.bufferingEvents.add(true);
    await tester.pump();
    expect(find.text('正在缓冲'), findsOneWidget);
    expect(find.text('缓冲 100%'), findsNothing);
  });

  testWidgets('old source events cannot update a replacement player', (
    tester,
  ) async {
    final old = FeedbackPlayer();
    final current = FeedbackPlayer();
    addTearDown(old.stream.close);
    addTearDown(current.stream.close);
    await tester.pumpWidget(surface(old));
    await tester.pumpWidget(surface(current));
    expect(
      tester
          .widget<PlayerBufferingOverlay>(find.byType(PlayerBufferingOverlay))
          .player,
      same(current),
    );
    expect(current.stream.bufferingEvents.hasListener, isTrue);
    expect(current.stream.percentageEvents.hasListener, isTrue);
    old.stream.bufferingEvents.add(true);
    old.stream.percentageEvents.add(80);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    current.stream.bufferingEvents.add(true);
    await tester.pump();
    await tester.pump();
    expect(find.text('正在缓冲'), findsOneWidget);
    current.stream.percentageEvents.add(20);
    await tester.pump();
    await tester.pump();
    expect(find.text('缓冲 20%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(current.stream.bufferingEvents.hasListener, isFalse);
    expect(current.stream.percentageEvents.hasListener, isFalse);
  });

  testWidgets('resolving and invalid progress remain indeterminate', (
    tester,
  ) async {
    await tester.pumpWidget(surface(null, resolving: true));
    expect(find.text('正在解析视频'), findsOneWidget);
    final player = FeedbackPlayer();
    addTearDown(player.stream.close);
    await tester.pumpWidget(surface(player));
    player.stream.bufferingEvents.add(true);
    player.stream.percentageEvents.add(double.nan);
    await tester.pump();
    expect(find.text('正在缓冲'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      isNull,
    );
  });
}
