import 'package:flutter/material.dart';

/// Katta ekranda: kontent chap menyudan ~1 sm uzoqda boshlanadi va enini
/// to'liq ishlatadi. Telefonda: markazda, oddiy kenglikda.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      if (!wide) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: child,
          ),
        );
      }
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: child,
          ),
        ),
      );
    });
  }
}

/// Butun oyna bo'ylab joylashadigan ro'yxat: keng ekranda kartalar 2–3 ustunga
/// bo'linadi (0-, 1-, 2-... kartalar ketma-ket ustunlarga), tor ekranda esa
/// oddiy bitta ustun. Bo'sh joy qolmaydi.
class ColumnsView extends StatelessWidget {
  const ColumnsView({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(16),
    this.minColWidth = 460,
    this.maxCols = 3,
    this.gap = 14,
    this.fullFirst = false,
  });
  final List<Widget> children;
  final EdgeInsets padding;
  final double minColWidth;
  final int maxCols;
  final double gap;

  /// true bo'lsa, birinchi karta (sarlavha) butun enga cho'ziladi.
  final bool fullFirst;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final c in this.children)
        if (!(c is SizedBox && c.child == null)) c,
    ];
    return LayoutBuilder(builder: (context, box) {
      final avail = box.maxWidth - padding.horizontal;
      var cols = (avail / minColWidth).floor().clamp(1, maxCols);
      if (box.maxWidth < 900) cols = 1;
      if (cols == 1) {
        return ListView(
          padding: padding,
          children: [
            for (final c in children) Padding(padding: EdgeInsets.only(bottom: gap), child: c),
          ],
        );
      }
      final head = fullFirst && children.isNotEmpty ? children.first : null;
      final rest = head == null ? children : children.sublist(1);
      final buckets = List.generate(cols, (_) => <Widget>[]);
      for (var i = 0; i < rest.length; i++) {
        buckets[i % cols].add(Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: rest[i],
        ));
      }
      return SingleChildScrollView(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (head != null) Padding(padding: EdgeInsets.only(bottom: gap), child: head),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: Column(children: buckets[i])),
                ],
              ],
            ),
          ],
        ),
      );
    });
  }
}
