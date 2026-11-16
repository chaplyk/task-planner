import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../collections.dart';

String triggerEmoji(String? triggerType) => switch (triggerType) {
      'time' => '⏰',
      'activity' => '🏃',
      'location' => '📍',
      _ => '📝',
    };

IconData triggerIcon(Map<String, dynamic> data) => switch (data['triggerType']) {
      'time' => Icons.schedule_rounded,
      'activity' => switch (data['activity']) {
          'IN_VEHICLE' => Icons.directions_car_rounded,
          'ON_BICYCLE' => Icons.directions_bike_rounded,
          'RUNNING' => Icons.directions_run_rounded,
          _ => Icons.directions_walk_rounded,
        },
      'location' => Icons.place_rounded,
      _ => Icons.notes_rounded,
    };

/// Streams a map of category name -> emoji.
Stream<Map<String, String>> categoryEmojiStream() => categoriesCollection().snapshots().map(
      (s) => {
        for (final d in s.docs) d.data()['name'] as String: d.data()['emoji'] as String? ?? '',
      },
    );

/// Whether a time reminder's moment has passed.
bool isOverdue(Map<String, dynamic> data) {
  final when = (data['when'] as Timestamp?)?.toDate();
  return data['triggerType'] == 'time' && when != null && when.isBefore(DateTime.now());
}

class ReminderTile extends StatefulWidget {
  const ReminderTile({
    super.key,
    required this.data,
    this.onTap,
    this.onToggle,
    this.done = false,
    this.highlight = false,
  });

  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  /// Completes an open reminder, or reopens a done one. Shows a checkbox when set.
  final VoidCallback? onToggle;
  final bool done;

  /// Briefly glows to draw attention to a just-created reminder.
  final bool highlight;

  @override
  State<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<ReminderTile> {
  // Shows the checkbox flipping before the row goes away.
  bool _ticking = false;

  Future<void> _toggle() async {
    if (widget.onToggle == null || _ticking) return;
    HapticFeedback.selectionClick();
    setState(() => _ticking = true);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    widget.onToggle!();
    if (mounted) setState(() => _ticking = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = widget.data;
    final done = widget.done;
    final checked = done != _ticking;
    final overdue = !done && isOverdue(data);
    final condition = data['condition'] as String?;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: widget.highlight ? scheme.primaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(22),
          boxShadow: widget.highlight
              ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 24)]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 12, widget.onToggle == null ? 16 : 4, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: overdue ? scheme.errorContainer : scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      triggerIcon(data),
                      size: 20,
                      color: overdue ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['summary'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: done ? scheme.onSurfaceVariant : null,
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (condition != null && condition.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            overdue ? 'Overdue · $condition' : condition,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: overdue ? scheme.error : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onToggle != null)
                    IconButton(
                      onPressed: _toggle,
                      tooltip: done ? 'Reopen' : 'Mark as done',
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          key: ValueKey(checked),
                          color: checked ? scheme.primary : scheme.outline,
                          size: 28,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Swipe right for the primary action (done / reopen), left to delete.
/// The parent must stop showing the row as soon as a swipe fires (see [onPrimary]/[onDelete]).
class SwipeableReminder extends StatelessWidget {
  const SwipeableReminder({
    super.key,
    required this.child,
    required this.onPrimary,
    required this.onDelete,
    this.primaryLabel = 'Done',
    this.primaryIcon = Icons.check_rounded,
  });

  final Widget child;
  final VoidCallback onPrimary;
  final VoidCallback onDelete;
  final String primaryLabel;
  final IconData primaryIcon;

  Widget _background(Color color, Color onColor, IconData icon, String label, Alignment align) {
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: align,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: key ?? UniqueKey(),
      background: _background(scheme.primary, scheme.onPrimary, primaryIcon, primaryLabel, Alignment.centerLeft),
      secondaryBackground: _background(
        scheme.error,
        scheme.onError,
        Icons.delete_outline_rounded,
        'Delete',
        Alignment.centerRight,
      ),
      onDismissed: (direction) {
        HapticFeedback.mediumImpact();
        direction == DismissDirection.startToEnd ? onPrimary() : onDelete();
      },
      child: child,
    );
  }
}

/// Placeholder shown immediately while a reminder is being understood.
class PendingTile extends StatefulWidget {
  const PendingTile({
    super.key,
    required this.text,
    this.failed = false,
    this.onTap,
    this.onDismiss,
  });

  final String text;
  final bool failed;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  State<PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<PendingTile> with SingleTickerProviderStateMixin {
  late final _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PendingTile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = !widget.failed && !MediaQuery.of(context).disableAnimations;
    if (animate && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!animate) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = widget.failed;
    final bg = failed ? scheme.errorContainer : scheme.surfaceContainer;

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: failed
              ? null
              : LinearGradient(
                  begin: Alignment(-1.5 + _shimmer.value * 3, 0),
                  end: Alignment(-0.5 + _shimmer.value * 3, 0),
                  colors: [bg, scheme.primaryContainer.withValues(alpha: 0.7), bg],
                ),
          color: failed ? bg : null,
        ),
        child: child,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: failed ? scheme.error : scheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    failed ? Icons.edit_rounded : Icons.auto_awesome_rounded,
                    color: failed ? scheme.onError : scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: failed ? scheme.onErrorContainer : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        failed ? "Couldn't understand · tap to fix" : 'Understanding…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: failed ? scheme.onErrorContainer : scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (failed && widget.onDismiss != null)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: scheme.onErrorContainer),
                    onPressed: widget.onDismiss,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
