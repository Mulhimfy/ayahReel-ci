import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Name prompt. Returns the trimmed name, an empty string to clear it,
/// or null when dismissed.
class NameDialog extends StatefulWidget {
  final String initial;
  const NameDialog({super.key, required this.initial});

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      title: Text(l.yourNameDialogTitle, style: t.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.yourNameDialogBody,
              style: t.bodySmall?.copyWith(
                  color: AppColors.textSecondary, height: 1.45)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            // A greeting is one word wide. Longer than this and the
            // home header spends two lines on a name.
            maxLength: 24,
            style: t.bodyMedium?.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: l.yourNameHint,
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.stroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(l.remove,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _save,
          child: Text(l.save,
              style: const TextStyle(color: AppColors.goldBright)),
        ),
      ],
    );
  }
}
