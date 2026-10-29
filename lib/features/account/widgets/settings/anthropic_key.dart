/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wger/features/nutrition/ai/meal_parser.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// Lets the user enter, replace or remove their own Anthropic API key
Future<void> showAnthropicKeyDialog(BuildContext context, WidgetRef ref) async {
  final i18n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(i18n.anthropicKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(i18n.anthropicKeyDescription),
          TextField(
            key: const Key('field-anthropic-key'),
            controller: controller,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'sk-ant-…'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          key: const Key('anthropic-key-delete'),
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(i18n.delete),
        ),
        TextButton(
          key: const Key('anthropic-key-save'),
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(i18n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result != null) {
    await ref.read(anthropicKeyProvider.notifier).setKey(result);
  }
}

class SettingsAnthropicKey extends ConsumerWidget {
  const SettingsAnthropicKey({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);
    final hasKey = ref.watch(anthropicKeyProvider).value != null;

    return ListTile(
      key: const Key('settings-anthropic-key'),
      title: Text(i18n.anthropicKey),
      subtitle: Text(hasKey ? i18n.anthropicKeySet : i18n.anthropicKeyMissing),
      trailing: const Icon(Icons.key),
      onTap: () => showAnthropicKeyDialog(context, ref),
    );
  }
}
