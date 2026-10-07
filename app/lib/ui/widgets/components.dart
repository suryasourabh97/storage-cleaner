import 'package:flutter/material.dart';

import '../theme.dart';

/// Page title, one line of explanation, and controls on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.displaySmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      subtitle!,
                      style: text.bodyMedium?.copyWith(
                        color: context.tokens.muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: 12), w],
        ],
      ),
    );
  }
}

/// Solid ink bar pinned to the bottom of a list page while something is
/// selected.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.summary,
    required this.actions,
  });

  final String summary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.ink,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    color: t.paper,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ),
              for (final a in actions) ...[const SizedBox(width: 12), a],
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary action on the ink selection bar: amber, the "reclaim" color.
class ReclaimButton extends StatelessWidget {
  const ReclaimButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.delete_outline,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: t.amber,
        foregroundColor: t.onAmber,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Quiet secondary action on the ink selection bar.
class BarTextButton extends StatelessWidget {
  const BarTextButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(foregroundColor: context.tokens.paper),
        onPressed: onPressed,
        child: Text(label),
      );
}

/// Group heading inside a list: name and totals, with an optional
/// select-all checkbox.
class GroupHeading extends StatelessWidget {
  const GroupHeading({
    super.key,
    required this.title,
    required this.detail,
    this.checkbox,
  });

  final String title;
  final String detail;
  final Widget? checkbox;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 32, 6),
      child: Row(
        children: [
          SizedBox(width: 40, child: checkbox),
          Text(title, style: text.titleMedium),
          const SizedBox(width: 12),
          Text(detail, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// One file in a list: checkbox, name over folder, notes, size column.
/// A selected row carries an amber marker on its left edge.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    required this.size,
    this.note,
    this.leading,
  });

  final bool selected;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;
  final String size;
  final String? note;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!selected) : null,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? t.surface : null,
          border: Border(
            left: BorderSide(
              color: selected ? t.amber : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(17, 8, 32, 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: leading ??
                  Checkbox(
                    value: selected,
                    onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                  ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: enabled ? t.ink : t.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: Text(size, style: sizeText(context), textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered message for empty or not-yet-scanned lists.
class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.title, this.body, this.action});
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                style: text.bodyMedium?.copyWith(color: context.tokens.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Compact dropdown used in page headers.
class InlineDropdown<T> extends StatelessWidget {
  const InlineDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(6),
        color: t.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(6),
            style: TextStyle(
              color: t.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final v in values)
                DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
