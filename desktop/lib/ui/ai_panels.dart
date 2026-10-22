import 'package:flutter/material.dart';

import 'shared.dart';

class AiPanel extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  final String? step;
  const AiPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.step,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .42)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: violet.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: violet, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (step != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      step!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: violet.withValues(alpha: .65),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class AiNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  const AiNotice(
    this.text, {
    super.key,
    this.icon = Icons.info_outline_rounded,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: violet.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: violet),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

InputDecoration aiInput(
  String? label, {
  String? hint,
  String? helper,
  IconData? icon,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  helperText: helper,
  helperMaxLines: 3,
  prefixIcon: icon == null ? null : Icon(icon, size: 19),
  alignLabelWithHint: true,
  filled: true,
  fillColor: violet.withValues(alpha: .035),
  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: violet.withValues(alpha: .18)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: violet.withValues(alpha: .15)),
  ),
);
