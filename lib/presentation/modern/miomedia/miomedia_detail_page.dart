import 'package:flutter/material.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import '../pages/sdk_player_detail_page.dart';

/// Existing callers keep their constructor; the player is shared with other SDKs.
class MioDetailPage extends StatefulWidget {
  const MioDetailPage({
    super.key,
    required this.item,
    this.service,
    this.autoPlay = false,
  });
  final MioVideo item;
  final MioMediaService? service;
  final bool autoPlay;
  @override
  State<MioDetailPage> createState() => _MioDetailPageState();
}

class _MioDetailPageState extends State<MioDetailPage> {
  late final service = widget.service ?? MioMediaService();
  late final entry = SdkPlaybackEntry(
    title: widget.item.title,
    cover: widget.item.cover,
    autoPlay: widget.autoPlay,
    sources: [
      SdkSourceBinding(
        provider: MioSdkPlaybackProvider(service),
        contentId: widget.item.id,
        seed: widget.item,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => SdkDetailPage(entry: entry);
  @override
  void dispose() {
    if (widget.service == null) service.dispose();
    super.dispose();
  }
}
