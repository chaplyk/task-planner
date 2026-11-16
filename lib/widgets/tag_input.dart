import 'package:material_ui/material_ui.dart';

/// Chips followed by a text field. A tag is submitted on comma, space,
/// enter or the add button.
class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.tags,
    required this.onAdd,
    required this.onDelete,
    this.hintText,
  });

  final List<String> tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onDelete;
  final String? hintText;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  static final _delimiters = RegExp(r'[, ]');
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final tag = value.trim();
    _controller.clear();
    if (tag.isNotEmpty) widget.onAdd(tag);
  }

  void _onChanged(String value) {
    if (!value.contains(_delimiters)) return;
    value.split(_delimiters).forEach(_submit);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < widget.tags.length; i++)
          Chip(
            label: Text(widget.tags[i]),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => widget.onDelete(i),
          ),
        IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _submit,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hintText,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _submit(_controller.text),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
