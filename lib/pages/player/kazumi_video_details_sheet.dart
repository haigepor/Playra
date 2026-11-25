import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_segmented_tab_bar.dart';

// Adapted from Kazumi GPL-3.0 video_details_sheet.dart at 906b144:
// https://github.com/Predidit/Kazumi/blob/906b144fbc6abb40b83bccf86354ba1751c316e6/lib/pages/player/video_details_sheet.dart
// PlayerDebugController deliberately retains only fixed-format summaries: do not
// introduce raw media URLs, native log messages, headers or track metadata here.
Future<void> showKazumiVideoDetailsSheet(
  BuildContext context, {
  required PlayerDebugController debug,
}) => showDialog<void>(
  context: context,
  builder: (context) => _VideoDetailsDialog(debug: debug),
);

class _VideoDetailsDialog extends StatelessWidget {
  const _VideoDetailsDialog({required this.debug});
  final PlayerDebugController debug;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: SizedBox(
        width: 680,
        height: size.height * .88,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '播放信息',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭播放信息',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const PlayraSegmentedTabBar(
                labels: ['概览', '日志'],
                horizontalPadding: 16,
                verticalPadding: 6,
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: PlayraHomeTokens.of(
                  context,
                ).divider.withValues(alpha: .6),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _Overview(debug: debug),
                    _Logs(debug: debug),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// These patterns match the controller's fixed-format numeric summaries only.
// Fail closed if a future controller accidentally supplies untrusted text.
final _videoParams = RegExp(r'^尺寸：\d+ × \d+，旋转：-?\d+°$');
final _audioParams = RegExp(r'^声道数：\d+，采样率：\d+ Hz$');
final _videoTrack = RegExp(r'^尺寸：\d+ × \d+，帧率：\d+(?:\.\d+)?$');
final _playlist = RegExp(r'^条目数：\d+，当前序号：(\d+|无)$');
const _safeLogs = {
  '播放器内核 · 致命（详细内容已隐藏）',
  '播放器内核 · 错误（详细内容已隐藏）',
  '播放器内核 · 警告（详细内容已隐藏）',
  '播放器内核 · 信息（详细内容已隐藏）',
  '播放器内核 · 调试（详细内容已隐藏）',
  '播放器内核 · 其他（详细内容已隐藏）',
};

String _summary(String value, RegExp pattern) =>
    pattern.hasMatch(value) ? value : '尚未获取';
String _bitrate(String value) {
  final number = double.tryParse(value);
  return number != null && number.isFinite && number >= 0 ? value : '尚未获取';
}

class _Overview extends StatelessWidget {
  const _Overview({required this.debug});
  final PlayerDebugController debug;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      final resolution = debug.playerWidth > 0 && debug.playerHeight > 0
          ? '${debug.playerWidth} × ${debug.playerHeight}'
          : '等待画面';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('画面与声音', style: Theme.of(context).textTheme.titleMedium),
          _field('分辨率', resolution),
          _field('视频码率', _bitrate(debug.playerVideoBitrate)),
          _field('音频码率', _bitrate(debug.playerAudioBitrate)),
          const Divider(),
          Text('媒体', style: Theme.of(context).textTheme.titleMedium),
          _field('播放列表', _summary(debug.playerPlaylist, _playlist)),
          const Divider(),
          Text('技术信息', style: Theme.of(context).textTheme.titleMedium),
          ExpansionTile(
            title: const Text('视频参数'),
            children: [
              _field('编码参数', _summary(debug.playerVideoParams, _videoParams)),
              _field('轨道', _summary(debug.playerVideoTracks, _videoTrack)),
            ],
          ),
          ExpansionTile(
            title: const Text('音频参数'),
            children: [
              _field('编码参数', _summary(debug.playerAudioParams, _audioParams)),
              _field('轨道', _summary(debug.playerAudioTracks, _audioParams)),
            ],
          ),
        ],
      );
    },
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), SelectableText(value)],
    ),
  );
}

class _Logs extends StatefulWidget {
  const _Logs({required this.debug});
  final PlayerDebugController debug;
  @override
  State<_Logs> createState() => _LogsState();
}

class _LogsState extends State<_Logs> {
  final _scroll = ScrollController();
  bool _initial = true;
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (_initial ||
          (count != _lastCount &&
              position.maxScrollExtent - position.pixels < 120)) {
        position.jumpTo(position.maxScrollExtent);
      }
      _initial = false;
      _lastCount = count;
    });
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      // Copy only recognized summaries; unexpected content is never exposed.
      final logs = widget.debug.playerLog
          .map((entry) => _safeLogs.contains(entry) ? entry : '播放器日志（内容已隐藏）')
          .toList();
      _follow(logs.length);
      return Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${logs.length} 条记录'),
              TextButton.icon(
                onPressed: logs.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: logs.join('\n')),
                      ),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: const Text('复制全部'),
              ),
            ],
          ),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('还没有运行日志'))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: logs.length,
                    itemBuilder: (context, index) => InkWell(
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: logs[index])),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Text(
                          logs[index],
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
