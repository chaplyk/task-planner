import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../llm/emoji.dart';

const maxCategories = 5;
const _pendingEmoji = '✨';

typedef _CategoryDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Label colors the user can pick from. The first one (brand coral) is the default.
const categoryColors = <int>[
  0xFFFE6D73, // coral
  0xFFFF9F43, // orange
  0xFFF6C344, // yellow
  0xFF4CC38A, // green
  0xFF2EC4B6, // teal
  0xFF4D96FF, // blue
  0xFF7B6CF6, // violet
  0xFFE36BAE, // pink
  0xFF8D99AE, // slate
];

/// Emoji the user can pick from in the category sheet.
const _emojiChoices = [
  '🧑', '🙂', '💼', '🏠', '🛒', '🩺', '💊', '🏋️', '🏃', '🚗', '✈️',
  '📚', '🎓', '💰', '🧾', '👨‍👩‍👧', '🧸', '🐾', '🍽️', '☕', '🎨',
  '🎵', '🎮', '🌱', '🧹', '🔧', '💻', '📞', '🎁', '❤️', '⭐',
];

/// A random palette color, preferring ones no other category uses yet.
int randomCategoryColor({Iterable<int?> used = const []}) {
  final taken = used.whereType<int>().toSet();
  final free = categoryColors.where((c) => !taken.contains(c)).toList();
  final pool = free.isEmpty ? categoryColors : free;
  return pool[Random().nextInt(pool.length)];
}

Color categoryColor(Map<String, dynamic> data) => Color((data['color'] as int?) ?? categoryColors.first);

/// Soft pill background and readable text color derived from a label color.
(Color, Color) bubbleColors(Color color, Brightness brightness) {
  final hsl = HSLColor.fromColor(color);
  if (brightness == Brightness.dark) {
    return (
      hsl.withLightness((hsl.lightness * 0.45).clamp(0.18, 0.32)).toColor(),
      hsl.withLightness(0.85).toColor(),
    );
  }
  return (
    hsl.withLightness(0.90).withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).toColor(),
    hsl.withLightness(0.28).toColor(),
  );
}

// Spread-out resting spots (fractions of the bubble area) for up to 5 bubbles.
const _slots = [
  Offset(0.27, 0.16),
  Offset(0.73, 0.30),
  Offset(0.30, 0.50),
  Offset(0.72, 0.68),
  Offset(0.32, 0.86),
];

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _controller = TextEditingController();
  final _backfilled = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  // Give emoji to categories created before emoji existed.
  void _backfill(List<_CategoryDoc> docs) {
    for (final doc in docs) {
      final emoji = doc.data()['emoji'] as String?;
      if ((emoji == null || emoji.isEmpty) && _backfilled.add(doc.id)) {
        suggestEmoji(doc['name'] as String)
            .then((e) => doc.reference.update({'emoji': e}));
      }
    }
  }

  Future<void> _add(List<_CategoryDoc> docs) async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (docs.length >= maxCategories) {
      _snack('You can only have up to $maxCategories categories');
      return;
    }
    final lower = name.toLowerCase();
    if (lower == 'other' ||
        docs.any((d) => (d['name'] as String).toLowerCase() == lower)) {
      _snack('This category already exists');
      return;
    }
    _controller.clear();
    FocusScope.of(context).unfocus();
    final ref = categoriesCollection().doc();
    sendWrite(ref.set({
      'name': name,
      'emoji': _pendingEmoji,
      'color': randomCategoryColor(used: docs.map((d) => d.data()['color'] as int?)),
    }));
    sendWrite(ref.update({'emoji': await suggestEmoji(name)}));
  }

  Future<void> _openDetails(_CategoryDoc doc) async {
    final data = doc.data();
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _CategorySheet(doc: doc),
    );
    if (delete != true || !mounted) return;
    sendWrite(doc.reference.delete());
    _snack(
      'Deleted "${data['name']}"',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => categoriesCollection().doc(doc.id).set(data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: categoriesCollection().snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        _backfill(docs);
        final full = docs.length >= maxCategories;

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: const Text('Categories'),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Used to sort your reminders · ${docs.length}/$maxCategories',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : docs.isEmpty
                        ? const _EmptyState()
                        : _BubbleField(docs: docs, onTap: _openDetails),
              ),
            ],
          ),
          bottomNavigationBar: _AddBar(
            controller: _controller,
            enabled: !full,
            onSubmit: () => _add(docs),
          ),
        );
      },
    );
  }
}

class _BubbleField extends StatelessWidget {
  const _BubbleField({required this.docs, required this.onTap});

  final List<_CategoryDoc> docs;
  final ValueChanged<_CategoryDoc> onTap;

  @override
  Widget build(BuildContext context) {
    // Fills the remaining space, but never shorter than 380 so bubbles have room.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 380),
      child: Stack(
        children: [
          for (var i = 0; i < docs.length && i < _slots.length; i++)
            Positioned.fill(
              key: ValueKey(docs[i].id),
              child: Align(
                alignment: Alignment(_slots[i].dx * 2 - 1, _slots[i].dy * 2 - 1),
                child: _FloatingBubble(
                  name: docs[i]['name'] as String,
                  emoji: docs[i].data()['emoji'] as String? ?? _pendingEmoji,
                  color: categoryColor(docs[i].data()),
                  seed: docs[i].id.hashCode,
                  onTap: () => onTap(docs[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingBubble extends StatefulWidget {
  const _FloatingBubble({
    required this.name,
    required this.emoji,
    required this.color,
    required this.seed,
    required this.onTap,
  });

  final String name;
  final String emoji;
  final Color color;
  final int seed;
  final VoidCallback onTap;

  @override
  State<_FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<_FloatingBubble>
    with TickerProviderStateMixin {
  late final Random _rand = Random(widget.seed);
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 4000 + _rand.nextInt(3000)),
  )..value = _rand.nextDouble();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();
  late final double _ampX = 6 + _rand.nextDouble() * 6;
  late final double _ampY = 8 + _rand.nextDouble() * 8;
  late final double _phase = _rand.nextDouble() * 2 * pi;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _drift.stop();
      _entrance.value = 1;
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubble = CategoryBubble(name: widget.name, emoji: widget.emoji, color: widget.color, onTap: widget.onTap);

    return AnimatedBuilder(
      animation: Listenable.merge([_drift, _entrance]),
      child: bubble,
      builder: (context, child) {
        final t = _drift.value * 2 * pi;
        final pop = Curves.elasticOut.transform(_entrance.value);
        return Opacity(
          opacity: _entrance.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(sin(t + _phase) * _ampX, sin(2 * t + _phase) * _ampY / 2),
            child: Transform.rotate(
              angle: sin(t + _phase) * 0.035,
              child: Transform.scale(scale: 0.6 + 0.4 * pop, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16, 8, 16, 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: enabled ? 'New category…' : 'Max $maxCategories categories',
                  prefixIcon: const Icon(Icons.sell_outlined),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: enabled ? onSubmit : null,
              iconSize: 26,
              padding: const EdgeInsets.all(14),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill with emoji and name. The shadow is painted outside the pill, so nothing
/// rectangular shows around its rounded edges.
class CategoryBubble extends StatelessWidget {
  const CategoryBubble({
    super.key,
    required this.name,
    required this.emoji,
    required this.color,
    this.onTap,
    this.large = false,
  });

  final String name;
  final String emoji;
  final Color color;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = bubbleColors(color, theme.brightness);
    const shape = StadiumBorder();
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: bg,
        shadows: [
          BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: large ? const EdgeInsets.fromLTRB(20, 14, 28, 14) : const EdgeInsets.fromLTRB(14, 10, 20, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Text(emoji, key: ValueKey(emoji), style: TextStyle(fontSize: large ? 36 : 26)),
                ),
                SizedBox(width: large ? 12 : 8),
                Text(
                  name,
                  style: (large ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits a category in place: emoji and color apply immediately.
/// Pops `true` when the user asks to delete it.
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.doc});

  final _CategoryDoc doc;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late String _emoji = widget.doc.data()['emoji'] as String? ?? fallbackEmoji;
  late Color _color = categoryColor(widget.doc.data());
  bool _suggesting = false;

  String get _name => widget.doc.data()['name'] as String;

  void _setEmoji(String emoji) {
    setState(() => _emoji = emoji);
    widget.doc.reference.update({'emoji': emoji});
  }

  void _setColor(Color color) {
    setState(() => _color = color);
    widget.doc.reference.update({'color': color.toARGB32()});
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    final emoji = await suggestEmoji(_name, avoid: _emoji);
    if (!mounted) return;
    setState(() => _suggesting = false);
    _setEmoji(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choices = [if (!_emojiChoices.contains(_emoji)) _emoji, ..._emojiChoices];

    Widget label(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(text, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              ?trailing,
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: CategoryBubble(name: _name, emoji: _emoji, color: _color, large: true)),
            const SizedBox(height: 28),
            label('Color'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final value in categoryColors)
                  _ColorSwatch(
                    color: Color(value),
                    selected: _color.toARGB32() == value,
                    onTap: () => _setColor(Color(value)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            label(
              'Emoji',
              trailing: TextButton.icon(
                onPressed: _suggesting ? null : _suggest,
                icon: _suggesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Suggest'),
              ),
            ),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final e in choices)
                  Material(
                    color: e == _emoji ? bubbleColors(_color, theme.brightness).$1 : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: e == _emoji ? BorderSide(color: _color, width: 2) : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _setEmoji(e),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? scheme.onSurface : Colors.transparent, width: 2),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(fallbackEmoji, style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'Add a category to start sorting your reminders',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
