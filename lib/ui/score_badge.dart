import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the number in the same place while the ice marker appears around it.
class ScoreBadge extends StatefulWidget {
  const ScoreBadge({
    super.key,
    required this.score,
    this.frozen = false,
    this.compact = false,
    this.onToggleFreeze,
  });
  final int score;
  final bool frozen, compact;
  final VoidCallback? onToggleFreeze;

  @override
  State<ScoreBadge> createState() => _ScoreBadgeState();
}

class _ScoreBadgeState extends State<ScoreBadge>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  @override
  void didUpdateWidget(ScoreBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frozen != oldWidget.frozen &&
        !MediaQuery.disableAnimationsOf(context)) {
      pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ice = Color(0xFFB9DFF3);
    final frozen = widget.frozen;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final hint = frozen
        ? 'Удержи цифру, чтобы снять фиксацию'
        : 'Удержи цифру, чтобы зафиксировать балл';
    return Semantics(
      label: 'Счёт ${widget.score}${frozen ? ', зафиксирован' : ''}',
      hint: widget.onToggleFreeze == null ? null : hint,
      onLongPress: widget.onToggleFreeze,
      child: ExcludeSemantics(
        child: Tooltip(
          message: hint,
          triggerMode: TooltipTriggerMode.tap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: widget.onToggleFreeze,
            child: SizedBox(
              width: widget.compact ? 28 : 52,
              height: 48,
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, child) => Transform.scale(
                  scale: 1 + math.sin(pulse.value * math.pi) * .12,
                  child: child,
                ),
                child: AnimatedContainer(
                  duration: duration,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: frozen
                        ? ice.withValues(alpha: .12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: frozen
                          ? ice.withValues(alpha: .55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${widget.score}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: widget.compact ? 14 : 17,
                              fontWeight: FontWeight.w700,
                              color: frozen
                                  ? ice
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 1,
                        right: 1,
                        child: AnimatedScale(
                          scale: frozen ? 1 : 0,
                          duration: duration,
                          child: Icon(
                            Icons.ac_unit_rounded,
                            size: 9,
                            color: ice,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
