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
