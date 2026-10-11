import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:kazumi/bean/card/user_comments_card.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/connected_tabs.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/pages/info/character_info_view.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

class CharacterPage extends StatefulWidget {
  const CharacterPage({
    super.key,
    required this.characterID,
    required this.characterName,
    required this.characterRelation,
    this.actorNames = const [],
    this.modern = false,
  });

  final int characterID;
  final String characterName;
  final String characterRelation;
  final List<String> actorNames;
  final bool modern;

  @override
  State<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends State<CharacterPage> {
  CharacterFullItem? _character;
  List<CharacterCommentItem> _comments = [];
  bool _loadingComments = true;
  bool _commentsError = false;

  Future<void> _loadCharacter() async {
    setState(() {
      _character = null;
    });
    final character = await BangumiApi.getCharacterByCharacterID(
      widget.characterID,
    );
    if (mounted) {
      setState(() {
        _character = character;
      });
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsError = false;
    });
    try {
      final response = await BangumiApi.getCharacterCommentsByCharacterID(
        widget.characterID,
      );
      if (!mounted) return;
      setState(() {
        _comments = response.commentList;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsError = true;
        _loadingComments = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCharacter();
      _loadComments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.modern
        ? ModernSecondaryScope(child: Builder(builder: _buildPage))
        : _buildPage(context);
  }

  Widget _buildPage(BuildContext context) {
    final name = widget.characterName.trim();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            MaterialBottomSheetHeader(
              title: name.isEmpty ? '人物' : name,
              onClose: () => Navigator.of(context).pop(),
            ),
            if (widget.modern)
              TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                indicator: UnderlineTabIndicator(
                  borderRadius: BorderRadius.circular(2),
                  borderSide: BorderSide(
                    width: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  insets: const EdgeInsets.symmetric(horizontal: 8),
                ),
                tabs: const [
                  Tab(height: 48, text: '资料'),
                  Tab(height: 48, text: '吐槽'),
                ],
              )
            else
              const ConnectedTabs(
                padding: materialBottomSheetTabsPadding,
                labels: ['资料', '吐槽'],
              ),
            Expanded(
              child: TabBarView(
                children: [_characterInfoBody, _characterCommentsBody],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget get _characterInfoBody {
    final character = _character;
    if (character != null && character.id == 0) {
      return GeneralErrorWidget(
        title: '人物资料加载失败',
        errMsg: '请检查网络连接后重试。',
        onRetry: _loadCharacter,
      );
    }

    if (character == null) {
      if (widget.modern) {
        return const SingleChildScrollView(
          padding: materialBottomSheetContentPadding,
          child: Skeletonizer.zone(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(height: 132, width: double.infinity, uniRadius: 12),
                SizedBox(height: 16),
                Bone.multiText(lines: 5),
              ],
            ),
          ),
        );
      }
      return const SingleChildScrollView(
        padding: materialBottomSheetContentPadding,
        child: Skeletonizer.zone(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(height: 300, width: double.infinity, uniRadius: 28),
              SizedBox(height: 24),
              Bone.multiText(lines: 5),
            ],
          ),
        ),
      );
    }
    return CharacterInfoView(
      character: character,
      characterName: widget.characterName,
      characterRelation: widget.characterRelation,
      actorNames: widget.actorNames,
    );
  }

  Widget get _characterCommentsBody {
    return CustomScrollView(
      scrollBehavior: const ScrollBehavior().copyWith(
        scrollbars: false,
        dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch},
      ),
      slivers: [
        SliverPadding(
          padding: materialBottomSheetContentPadding,
          sliver: _commentsSliver,
        ),
      ],
    );
  }

  Widget get _commentsSliver {
    if (_loadingComments) {
      return SliverList.builder(
        itemCount: 3,
        itemBuilder: (context, _) => const UserCommentsCardBone(),
      );
    }
    if (_commentsError) {
      return SliverFillRemaining(
        child: GeneralErrorWidget(
          title: '人物吐槽加载失败',
          errMsg: '请检查网络连接后重试。',
          onRetry: _loadComments,
        ),
      );
    }
    if (_comments.isEmpty) {
      if (widget.modern) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: SecondaryEmptyState(
            title: '还没有评论',
            description: '这里会展示人物相关的吐槽。',
            asset: 'modern-player-empty-discussion',
          ),
        );
      }
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: GeneralEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: '还没有评论',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Keep loaded images alive to prevent scroll jumps.
          return KeepAlive(
            keepAlive: true,
            child: IndexedSemantics(
              index: index,
              child: UserCommentsCard.character(_comments[index]),
            ),
          );
        },
        childCount: _comments.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
      ),
    );
  }
}
