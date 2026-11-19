import 'package:material_ui/material_ui.dart';

import '../core/utils/validators.dart';

/// Opens a mandatory-remark dialog for reject/flag actions.
///
/// Returns the trimmed remark, or `null` if the user cancels. The confirm
/// button cannot submit an empty remark.
Future<String?> showRemarkDialog({
  required BuildContext context,
  required String title,
  required String description,
  required String confirmLabel,
  Color? confirmColor,
  List<String> suggestions = const <String>[],
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _RemarkDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      suggestions: suggestions,
    ),
  );
}

class _RemarkDialog extends StatefulWidget {
  const _RemarkDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    this.confirmColor,
    required this.suggestions,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final Color? confirmColor;
  final List<String> suggestions;

  @override
  State<_RemarkDialog> createState() => _RemarkDialogState();
}

class _RemarkDialogState extends State<_RemarkDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color confirmColor = widget.confirmColor ?? theme.colorScheme.error;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.description),
              const SizedBox(height: 14),
              TextFormField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                validator: Validators.remarks,
                decoration: const InputDecoration(
                  labelText: 'Remark (required)',
                  hintText: 'Explain exactly what needs to be corrected…',
                  alignLabelWithHint: true,
                ),
              ),
              if (widget.suggestions.isNotEmpty) ...<Widget>[
                Text(
                  'Quick reasons',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.suggestions
                      .map(
                        (String suggestion) => ActionChip(
                          label: Text(
                            suggestion,
                            style: theme.textTheme.labelSmall,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          onPressed: () {
                            _controller.text = suggestion;
                            _controller.selection =
                                TextSelection.collapsed(
                              offset: suggestion.length,
                            );
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Standard confirmation dialog. Returns true only when confirmed.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ThemeData theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
