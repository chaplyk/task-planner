import 'package:material_ui/material_ui.dart';

import '../llm/emoji.dart';

/// Emoji offered for tasks and routines, besides the current one.
const taskEmojiChoices = [
  '📝', '⏰', '📞', '💬', '📧', '💼', '💻', '📅', '🏠', '🧹', '🧺', '🍽️',
  '🛒', '🎁', '💳', '🧾', '💰', '🏦', '🩺', '💊', '🦷', '🏋️', '🏃', '🧘',
  '🌱', '💧', '🐕', '🐈', '🚗', '⛽', '✈️', '🧳', '📚', '🎓', '🎨', '🎵',
  '🎮', '☕', '🍳', '🥗', '🎂', '❤️', '👶', '👨‍👩‍👧', '🔧', '💾', '🗑️', '⭐',
];

/// Lets the user pick an emoji for [subject] (a task or routine name). Returns null if dismissed.
Future<String?> pickEmoji(BuildContext context, {required String current, required String subject}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _EmojiPicker(current: current, subject: subject),
  );
}

class _EmojiPicker extends StatefulWidget {
  const _EmojiPicker({required this.current, required this.subject});

  final String current;
  final String subject;

  @override
  State<_EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<_EmojiPicker> {
  bool _suggesting = false;

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    final emoji = await suggestEmoji(widget.subject, avoid: widget.current, task: true);
    if (mounted) Navigator.pop(context, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = widget.current;
    final choices = [if (!taskEmojiChoices.contains(current)) current, ...taskEmojiChoices];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Emoji', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _suggesting || widget.subject.trim().isEmpty ? null : _suggest,
                  icon: _suggesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Suggest'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final e in choices)
                  Material(
                    color: e == current ? scheme.primaryContainer : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: e == current ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(context, e),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
