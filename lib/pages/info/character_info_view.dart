import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/image_preview.dart';
import 'package:kazumi/bean/widget/tonal_card.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

class CharacterInfoView extends StatelessWidget {
  const CharacterInfoView({
    super.key,
    required this.character,
    required this.characterName,
    required this.characterRelation,
    this.actorNames = const [],
  });

  final CharacterFullItem character;
  final String characterName;
  final String characterRelation;
  final List<String> actorNames;

  static const _quickKeys = {'性别', '生日', '年龄', '身高', '体重', '血型'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modern = ModernSecondaryScope.isActiveOf(context);
    final fields =
        character.infobox.where((field) => field.key != '引用来源').toList();
    final quickFields = fields
        .where((field) => _quickKeys.contains(field.key))
        .take(4)
        .toList();
    final moreFields = fields
        .where((field) => field.key != '简体中文名' && !quickFields.contains(field))
        .toList();
    final tappedName = characterName.trim();
    final originalName =
        character.name.isNotEmpty ? character.name : tappedName;
    final name = character.nameCn.isNotEmpty
        ? character.nameCn
        : tappedName.isNotEmpty
            ? tappedName
            : originalName;
    final useCompactColumns = MediaQuery.textScalerOf(context).scale(14) <= 20;
    final relation = characterRelation.trim();

    if (modern) {
      return _modernBody(context,
          name: name,
          originalName: originalName,
          relation: relation,
          quickFields: quickFields,
          moreFields: moreFields);
    }

    final profile = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TonalCard(
          padding: EdgeInsets.all(modern ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (relation.isNotEmpty && relation != '未知') ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(relation,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      )),
                ),
                const SizedBox(height: 12),
              ],
              SelectableText(
                name.isEmpty ? '人物' : name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (originalName.isNotEmpty && originalName != name) ...[
                const SizedBox(height: 8),
                SelectableText(originalName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
              if (actorNames.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildInfoField(context, '配音', actorNames.join(' / ')),
              ],
            ],
          ),
        ),
        if (quickFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          ContentSection(
            title: '基本资料',
            child: LayoutBuilder(builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 240 && useCompactColumns ? 2 : 1;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final field in quickFields)
                    SizedBox(
                      width:
                          (constraints.maxWidth - 16 * (columns - 1)) / columns,
                      child: _buildInfoField(context, field.key, field.value),
                    ),
                ],
              );
            }),
          ),
        ],
      ],
    );

    return SingleChildScrollView(
      key: const PageStorageKey('character-info'),
      padding: materialBottomSheetContentPadding,
      child: LayoutBuilder(builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= (modern ? 260 : 480) && useCompactColumns;
        final portraitWidth =
            modern ? 88.0 : sideBySide ? constraints.maxWidth * 0.40 : constraints.maxWidth;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final portraitHeight = modern ? 132.0 : sideBySide
            ? (screenHeight * 0.42).clamp(240.0, 400.0)
            : (screenHeight * 0.30).clamp(200.0, 300.0);
        final portrait = _CharacterPortrait(
          imageUrl: character.image,
          width: portraitWidth,
          height: portraitHeight,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: portraitWidth, child: portrait),
                  const SizedBox(width: 16),
                  Expanded(child: profile),
                ],
              )
            else ...[
              portrait,
              const SizedBox(height: 16),
              profile,
            ],
            if (character.summary.isNotEmpty) ...[
              const SizedBox(height: 24),
              ContentSection(
                title: '人物简介',
                child: SelectableText(character.summary,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.65)),
              ),
            ],
            if (moreFields.isNotEmpty) ...[
              const SizedBox(height: 24),
              ContentSection.group(
                title: '更多资料',
                children: [
                  for (final field in moreFields)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildInfoField(context, field.key, field.value),
                    ),
                ],
              ),
            ],
            if (character.unstructuredInfo.isNotEmpty) ...[
              const SizedBox(height: 24),
              ContentSection(
                title: '人物资料',
                child: SelectableText(character.unstructuredInfo,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
              ),
            ],
            if (fields.isEmpty &&
                character.unstructuredInfo.isEmpty &&
                character.summary.isEmpty) ...[
              const SizedBox(height: 24),
              const TonalCard(
                child: GeneralEmptyState(
                  icon: Icons.person_outline_rounded,
                  title: '暂无人物资料',
                  compact: true,
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _modernBody(
    BuildContext context, {
    required String name,
    required String originalName,
    required String relation,
    required List<CharacterInfoField> quickFields,
    required List<CharacterInfoField> moreFields,
  }) {
    final theme = Theme.of(context);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (relation.isNotEmpty && relation != '未知') ...[
          Text(relation,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
        ],
        SelectableText(name.isEmpty ? '人物' : name,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (originalName.isNotEmpty && originalName != name) ...[
          const SizedBox(height: 6),
          SelectableText(originalName,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
        if (actorNames.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildInfoField(context, '配音', actorNames.join(' / ')),
        ],
      ],
    );
    return SingleChildScrollView(
      key: const PageStorageKey('character-info'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: LayoutBuilder(builder: (context, constraints) {
        final compactColumns = MediaQuery.textScalerOf(context).scale(14) <= 20;
        final sideBySide = constraints.maxWidth >= 260 && compactColumns;
        final portrait = _CharacterPortrait(
            imageUrl: character.image, width: 88, height: 132);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideBySide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                portrait,
                const SizedBox(width: 16),
                Expanded(child: identity),
              ])
            else ...[
              Align(alignment: Alignment.centerLeft, child: portrait),
              const SizedBox(height: 12),
              identity,
            ],
            // 基本资料独占整行，避免被头像右侧的窄列压缩。
            if (quickFields.isNotEmpty)
              _modernSection(context, '基本资料',
                  child: LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 280 && compactColumns ? 2 : 1;
                return Wrap(spacing: 16, runSpacing: 12, children: [
                  for (final field in quickFields)
                    SizedBox(
                        width: (box.maxWidth - 16 * (columns - 1)) / columns,
                        child: _buildInfoField(context, field.key, field.value)),
                ]);
              })),
            if (character.summary.isNotEmpty)
              _modernSection(context, '人物简介',
                  child: SelectableText(character.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6))),
            if (moreFields.isNotEmpty)
              _modernSection(context, '更多资料',
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in moreFields)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildInfoField(
                                  context, field.key, field.value)),
                      ])),
            if (character.unstructuredInfo.isNotEmpty)
              _modernSection(context, '人物资料',
                  child: SelectableText(character.unstructuredInfo,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6))),
            if (quickFields.isEmpty &&
                moreFields.isEmpty &&
                character.summary.isEmpty &&
                character.unstructuredInfo.isEmpty) ...[
              const SizedBox(height: 20),
              const GeneralEmptyState(
                  icon: LucideIcons.userRound,
                  title: '暂无人物资料',
                  compact: true),
            ],
          ],
        );
      }),
    );
  }

  Widget _modernSection(BuildContext context, String title,
      {required Widget child}) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

Widget _buildInfoField(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
      const SizedBox(height: 4),
      SelectableText(value,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
    ],
  );
}

class _CharacterPortrait extends StatelessWidget {
  const _CharacterPortrait({
    required this.imageUrl,
    required this.width,
    required this.height,
  });

  final String imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (ModernSecondaryScope.isActiveOf(context)) {
      final hasImage = imageUrl.isNotEmpty;
      return SizedBox(
        width: width,
        height: height,
        child: Semantics(
          button: hasImage,
          label: hasImage ? '查看人物原图' : '暂无人物图片',
          child: Tooltip(
            message: hasImage ? '查看人物原图' : '暂无人物图片',
            excludeFromSemantics: true,
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: hasImage
                    ? () => ImageViewer.show(context,
                        imageUrls: [imageUrl],
                        heroTag: ImageViewer.heroTagFor(imageUrl, 0))
                    : null,
                child: ExcludeSemantics(
                  child: hasImage
                      ? Stack(children: [
                          Hero(
                            tag: ImageViewer.heroTagFor(imageUrl, 0),
                            child: NetworkImgLayer(
                                src: imageUrl,
                                width: width,
                                height: height,
                                fit: BoxFit.contain,
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: .8),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(LucideIcons.maximize2,
                                    size: 14, color: colors.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ])
                      : Center(
                          child: Icon(LucideIcons.userRound,
                              size: 24, color: colors.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (imageUrl.isEmpty) {
      return const TonalCard(
        child: SizedBox(
          height: 160,
          child: GeneralEmptyState(
            icon: Icons.person_outline_rounded,
            title: '暂无人物图片',
            compact: true,
          ),
        ),
      );
    }
    final heroTag = ImageViewer.heroTagFor(imageUrl, 0);

    return Semantics(
      button: true,
      label: '查看人物原图',
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ModernSecondaryScope.isActiveOf(context) ? 12 : 28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ImageViewer.show(
            context,
            imageUrls: [imageUrl],
            heroTag: heroTag,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Hero(
                  tag: heroTag,
                  child: NetworkImgLayer(
                    src: imageUrl,
                    width: width - 24,
                    height: height,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.zoom_in_rounded,
                          size: 20, color: colors.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('查看原图',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: colors.primary)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
