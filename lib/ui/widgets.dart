import 'package:flutter/material.dart';

import '../domain/lang.dart';
import 'theme.dart';

/// The orange pill used for the main action of a screen.
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, this.icon, this.onPressed, this.height = 56});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(height / 2)),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(height / 2),
              onTap: onPressed,
              child: SizedBox(
                height: height,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10)],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navy outlined pill for secondary actions.
class OutlinePill extends StatelessWidget {
  const OutlinePill({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 48,
    this.color = C.brand,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: onPressed == null ? C.hairline : color),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
  );
}

/// A row of pill-shaped single-choice chips.
class PillChoices<T> extends StatelessWidget {
  const PillChoices({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        ChoiceChip(
          label: Text(label(v)),
          selected: v == selected,
          showCheckmark: false,
          onSelected: onChanged == null ? null : (_) => onChanged!(v),
          labelStyle: TextStyle(
            fontSize: 15,
            color: v == selected ? Colors.white : C.ink,
            fontWeight: v == selected ? FontWeight.w500 : FontWeight.w400,
          ),
          selectedColor: C.brand,
          backgroundColor: C.surface,
          side: BorderSide(color: v == selected ? C.brand : C.hairline),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
    ],
  );
}

class LangChoices extends StatelessWidget {
  const LangChoices({super.key, required this.selected, required this.onChanged, this.values = Lang.values});
  final Lang selected;
  final ValueChanged<Lang>? onChanged;
  final List<Lang> values;

  @override
  Widget build(BuildContext context) =>
      PillChoices<Lang>(values: values, selected: selected, label: (l) => l.label, onChanged: onChanged);
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.inkMuted),
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: C.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: C.hairline),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A banner for problems (lost connection, missing key…).
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.text, this.action, this.onAction, this.action2, this.onAction2});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final String? action2;
  final VoidCallback? onAction2;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: C.warningSoft,
    padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, color: C.warning)),
        ),
        if (action2 != null) TextButton(onPressed: onAction2, child: Text(action2!)),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
