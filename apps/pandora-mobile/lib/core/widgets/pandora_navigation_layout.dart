import 'package:flutter/material.dart';

/// Header and actions occupy real layout space; rows cannot paint or receive
/// taps beneath them. Short viewports scroll the complete layout instead of
/// overflowing while the keyboard or large accessibility text takes space.
class PandoraNavigationLayout extends StatelessWidget {
  const PandoraNavigationLayout({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
    required this.controller,
    required this.scrollKey,
    this.bodyPadding = EdgeInsets.zero,
  });
  final Widget header;
  final Widget body;
  final Widget footer;
  final ScrollController controller;
  final Key scrollKey;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    if (constraints.maxHeight < 300) {
      return SingleChildScrollView(
        key: scrollKey, controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header, Padding(padding: bodyPadding, child: body), footer,
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(child: SingleChildScrollView(
        key: scrollKey, controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: bodyPadding, child: body,
      )),
      footer,
    ]);
  });
}
