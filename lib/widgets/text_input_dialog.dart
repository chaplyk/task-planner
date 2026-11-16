import 'package:material_ui/material_ui.dart';

/// Shows a dialog with a single text field. Returns the trimmed text, or null
/// if dismissed.
///
/// The controller lives in the dialog's State, so it is disposed only after the
/// exit animation finishes. Disposing it when showDialog's future completes
/// crashes, because the TextField still rebuilds while the dialog fades out.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hintText,
  bool filledAction = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      action: action,
      initial: initial,
      hintText: hintText,
      filledAction: filledAction,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.action,
    required this.initial,
    this.hintText,
    required this.filledAction,
  });

  final String title;
  final String action;
  final String initial;
  final String? hintText;
  final bool filledAction;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final action = Text(widget.action);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        widget.filledAction
            ? FilledButton(onPressed: _submit, child: action)
            : TextButton(onPressed: _submit, child: action),
      ],
    );
  }
}
