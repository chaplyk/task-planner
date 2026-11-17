import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/recurrence.dart';
import '../recurring_repo.dart';

enum RoutineAction { done, history, edit, skip, delete }

/// Grid card: a ring showing how much of the cycle is left around the routine's emoji.
/// Press and hold to mark it done (a second ring fills while holding); a tap opens its history;
/// the ⋯ menu marks done, edits, skips or deletes it.
class RoutineCard extends StatefulWidget {
  const RoutineCard({
    super.key,
    required this.routine,
    required this.now,
    required this.onDone,
    required this.onAction,
  });

  final Routine routine;
  final DateTime now;
  final VoidCallback onDone;
  final ValueChanged<RoutineAction> onAction;

  @override
  State<RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<RoutineCard> with TickerProviderStateMixin {
  // Fills while the finger is down; completing it marks the routine done.
  late final _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    reverseDuration: const Duration(milliseconds: 220),
  )..addStatusListener(_onHoldStatus);

  // The "done" pop: emoji bounces, a check flashes over it.
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  bool _holding = false;

  // The hold finished while the finger is still down: its release is not a tap.
  bool _swallowTap = false;

  @override
  void dispose() {
    _hold.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_holding) return;
    _holding = false;
    _swallowTap = true;
    HapticFeedback.heavyImpact();
    _pop.forward(from: 0);
    _hold.value = 0;
    widget.onDone();
  }

  void _start() {
    _holding = true;
    _swallowTap = false;
    HapticFeedback.selectionClick();
    _hold.forward();
  }

  void _cancel() {
    if (!_holding) return;
    _holding = false;
    _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final routine = widget.routine;
    final due = routine.isDue(widget.now);
    final share = remainingShare(widget.now, routine.periodStart, routine.nextDue);

    return AnimatedBuilder(
      animation: Listenable.merge([_hold, _pop]),
      builder: (context, child) {
        final hold = Curves.easeOut.transform(_hold.value);
        return Transform.scale(scale: 1 - 0.05 * hold, child: child);
      },
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _start(),
          onTapUp: (_) => _cancel(),
          onTapCancel: _cancel,
          // Released before the ring closed: a plain tap shows when it was done or skipped.
          onTap: () {
            if (_swallowTap) {
              _swallowTap = false;
              return;
            }
            widget.onAction(RoutineAction.history);
          },
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: share),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => AnimatedBuilder(
                              animation: Listenable.merge([_hold, _pop]),
                              builder: (context, _) => CustomPaint(
                                painter: _RingPainter(
                                  share: v,
                                  hold: _hold.value,
                                  track: scheme.surfaceContainerHighest,
                                  arc: due ? scheme.error : scheme.primary,
                                  holdColor: scheme.tertiary,
                                ),
                                child: _center(scheme),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      routine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: _hold,
                      builder: (context, _) {
                        final holding = _hold.value > 0;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            holding ? 'Hold to finish…' : dueLabel(widget.now, routine.nextDue),
                            key: ValueKey(holding),
                            maxLines: 1,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: holding
                                  ? scheme.tertiary
                                  : due
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: PopupMenuButton<RoutineAction>(
                  tooltip: 'More',
                  onSelected: (a) {
                    if (a == RoutineAction.done) {
                      HapticFeedback.mediumImpact();
                      _pop.forward(from: 0);
                    }
                    widget.onAction(a);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: RoutineAction.done,
                      child: ListTile(leading: Icon(Icons.check_rounded), title: Text('Mark as done')),
                    ),
                    PopupMenuItem(
                      value: RoutineAction.skip,
                      child: ListTile(leading: Icon(Icons.skip_next_rounded), title: Text('Skip this time')),
                    ),
                    PopupMenuItem(
                      value: RoutineAction.edit,
                      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                    ),
                    PopupMenuItem(
                      value: RoutineAction.delete,
                      child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete')),
                    ),
                  ],
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
                    child: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Emoji in the middle; pops and shows a check when the routine is marked done.
  Widget _center(ColorScheme scheme) {
    final p = _pop.value;
    final popping = _pop.isAnimating;
    // Up to 1.35x and back, with a little overshoot.
    final bounce = popping ? 1 + 0.35 * math.sin(math.pi * Curves.easeOut.transform(p)) : 1.0;
    final grow = 1 + 0.12 * Curves.easeOut.transform(_hold.value);
    // The check fades in quickly, then out.
    final check = popping ? (p < 0.25 ? p / 0.25 : (1 - (p - 0.25) / 0.75)).clamp(0.0, 1.0) : 0.0;
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.46,
        heightFactor: 0.46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 1 - check * 0.85,
              child: Transform.scale(
                scale: bounce * grow,
                child: FittedBox(child: Text(widget.routine.emoji, style: const TextStyle(fontSize: 40))),
              ),
            ),
            if (check > 0)
              Opacity(
                opacity: check,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * check,
                  child: FittedBox(child: Icon(Icons.check_circle_rounded, color: scheme.primary, size: 40)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.share,
    required this.hold,
    required this.track,
    required this.arc,
    required this.holdColor,
  });

  /// Share of the cycle left (1 = just done, 0 = due).
  final double share;

  /// Press-and-hold progress, drawn as a second arc on top.
  final double hold;
  final Color track;
  final Color arc;
  final Color holdColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    Paint paint(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint(track));
    // A due routine shows a full ring in the alert colour rather than an empty one.
    final sweep = share <= 0 ? 2 * math.pi : 2 * math.pi * share;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint(arc));
    if (hold > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * hold, false, paint(holdColor));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.hold != hold || old.track != track || old.arc != arc || old.holdColor != holdColor;
}
