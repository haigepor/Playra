import 'package:flutter/material.dart';
import 'app_bar.dart';
import 'extensions.dart';

/// 官方示例容器的手机适配：窄屏将属性面板放在底部。
class BaseScaffold extends StatelessWidget {
  const BaseScaffold({
    super.key,
    required this.children,
    required this.appBarTitle,
    this.editable,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.wrapChildrenInScrollable = true,
    this.wrapSingleChildInColumn = true,
    this.alignment,
    this.gap = 8,
  });
  final List<Widget> children;
  final String appBarTitle;
  final List<Widget>? editable;
  final CrossAxisAlignment crossAxisAlignment;
  final bool wrapChildrenInScrollable;
  final bool wrapSingleChildInColumn;
  final Alignment? alignment;
  final double gap;

  @override
  Widget build(BuildContext context) {
    Widget demo = Align(
      alignment: alignment ?? Alignment.center,
      child: children.length == 1 && !wrapSingleChildInColumn
          ? children.first
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: crossAxisAlignment,
              children: children.separatedBy(SizedBox(height: gap)),
            ),
    );
    if (wrapChildrenInScrollable) {
      demo = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: demo,
      );
    }
    final properties = editable == null
        ? null
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: editable!.separatedBy(SizedBox(height: gap)),
            ),
          );
    return Scaffold(
      appBar: MyAppBar(title: appBarTitle),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (properties == null) return demo;
            if (constraints.maxWidth >= 720) {
              return Row(
                children: [
                  Expanded(child: demo),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 280, child: properties),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: demo),
                const Divider(height: 1),
                SizedBox(height: constraints.maxHeight * .3, child: properties),
              ],
            );
          },
        ),
      ),
    );
  }
}
