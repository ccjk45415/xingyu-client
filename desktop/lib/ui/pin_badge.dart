import 'package:flutter/material.dart';

import 'shared.dart';

class PinBadge extends StatelessWidget {
  final bool onCover;
  const PinBadge({super.key, this.onCover = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: onCover ? const Color(0xff7960cd) : violet.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.push_pin_rounded,
          size: 12,
          color: onCover ? Colors.white : violet,
        ),
        const SizedBox(width: 4),
        Text(
          '置顶',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: onCover ? Colors.white : violet,
          ),
        ),
      ],
    ),
  );
}
