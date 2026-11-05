import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/bazarr_service.dart';
import '../../../preference/bazarr_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';

/// Direct Bazarr connection settings (URL + API key), separate from
/// Emby's own subtitle search. Sid: "le mien c'est lien direct vers
/// bazarr" - deliberately simple compared to seerr_config_screen.dart
/// (no rows, profiles, root folders - just enough to reach one Bazarr
/// instance and let the subtitle search action below use it when
/// configured).
class BazarrConfigScreen extends StatefulWidget {
  const BazarrConfigScreen({super.key});

  @override
  State<BazarrConfigScreen> createState() => _BazarrConfigScreenState();
}

class _BazarrConfigScreenState extends State<BazarrConfigScreen> {
  late final BazarrPreferences _prefs = GetIt.instance<BazarrPreferences>();
  late final BazarrService _service = GetIt.instance<BazarrService>();

  late final TextEditingController _urlController = TextEditingController(
    text: _prefs.serverUrl,
  );
  late final TextEditingController _apiKeyController = TextEditingController(
    text: _prefs.apiKey,
  );
  late bool _enabled = _prefs.enabled;
  bool _obscureApiKey = true;
  bool _testing = false;
  String? _testResult;
  bool _testSucceeded = false;

  // 06.11, Sid ("je ne peux pas sortir du champ de l'adresse IP avec le
  // D-pad") - un `TextField` brut capte les flèches Haut/Bas pour le
  // déplacement du curseur de texte sur TV, empêchant toute sortie du
  // champ. Même pattern que server_select_screen.dart/seerr_config_
  // screen.dart (`CustomTVTextField` + `Focus.onKeyEvent` gérant
  // explicitement Haut/Bas) - jamais appliqué ici puisque cet écran a été
  // créé avec de simples `TextField` (03.11), sans qu'un vrai test D-pad
  // sur TV n'ait eu lieu avant ce soir.
  final _enabledFocus = FocusNode(debugLabel: 'bazarrEnabled');
  final _urlFocus = FocusNode(debugLabel: 'bazarrUrl');
  final _apiKeyFocus = FocusNode(debugLabel: 'bazarrApiKey');
  final _testFocus = FocusNode(debugLabel: 'bazarrTest');
  final _urlTvFieldKey = GlobalKey<CustomTVTextFieldState>();
  final _apiKeyTvFieldKey = GlobalKey<CustomTVTextFieldState>();

  @override
  void initState() {
    super.initState();
    // `SwitchListTile`/`FilledButton` acceptent déjà un `focusNode` natif -
    // assigner `onKeyEvent` directement dessus plutôt que les envelopper
    // dans un `Focus` séparé (qui créerait un second niveau de focus en
    // plus de celui, interne, du widget Material lui-même).
    _enabledFocus.onKeyEvent = _onEnabledKey;
    _testFocus.onKeyEvent = _onTestKey;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _enabledFocus.dispose();
    _urlFocus.dispose();
    _apiKeyFocus.dispose();
    _testFocus.dispose();
    super.dispose();
  }

  // Ouvre/ferme le clavier virtuel TV au Entrée/Select/Retour - même
  // logique que seerr_config_screen.dart's `_handleTvFieldOpen`.
  bool _handleTvFieldOpen(
    KeyEvent event,
    FocusNode focusNode,
    GlobalKey<CustomTVTextFieldState> fieldKey,
  ) {
    if (!PlatformDetection.isTV) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (event.logicalKey.isBackKey) {
      if (event is KeyDownEvent &&
          (fieldKey.currentState?.isKeyboardVisible ?? false)) {
        fieldKey.currentState?.closeKeyboard();
        focusNode.requestFocus();
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (!focusNode.hasFocus) focusNode.requestFocus();
      fieldKey.currentState?.openKeyboard();
      return true;
    }

    return false;
  }

  KeyEventResult _onEnabledKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _urlFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onUrlKey(FocusNode node, KeyEvent event) {
    if (_handleTvFieldOpen(event, node, _urlTvFieldKey)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _apiKeyFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _enabledFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onApiKeyKey(FocusNode node, KeyEvent event) {
    if (_handleTvFieldOpen(event, node, _apiKeyTvFieldKey)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _testFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _urlFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onTestKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _apiKeyFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required GlobalKey<CustomTVTextFieldState> tvFieldKey,
    required KeyEventResult Function(FocusNode, KeyEvent) onTvKey,
    required TextFieldType tvType,
    Widget? mobileSuffixIcon,
  }) {
    if (PlatformDetection.isTV) {
      final colorScheme = Theme.of(context).colorScheme;
      return Focus(
        focusNode: focusNode,
        onKeyEvent: onTvKey,
        child: ListenableBuilder(
          listenable: focusNode,
          builder: (_, _) {
            final focused = focusNode.hasFocus;
            return CustomTVTextField(
              key: tvFieldKey,
              controller: controller,
              isFocused: focused,
              inputPurpose: tvType == TextFieldType.url
                  ? InputPurpose.url
                  : InputPurpose.text,
              hint: hint,
              textFieldType: tvType,
              keyboardType: KeyboardType.alphabetic,
              filled: true,
              fillColor: focused
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
              borderColor: colorScheme.outline,
              focusedBorderColor: colorScheme.primary,
              hintStyle: TextStyle(
                fontFamily: kCleanSettingsFontFamily,
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              textStyle: TextStyle(
                fontFamily: kCleanSettingsFontFamily,
                color: colorScheme.onSurface,
              ),
              popParentOnKeyboardClose: false,
              onFieldSubmitted: (_) => unawaited(_save()),
            );
          },
        ),
      );
    }

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: tvType == TextFieldType.password,
      keyboardType: tvType == TextFieldType.url
          ? TextInputType.url
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: mobileSuffixIcon,
      ),
      onEditingComplete: () => unawaited(_save()),
    );
  }

  Future<void> _save() async {
    await _prefs.setServerUrl(_urlController.text.trim());
    await _prefs.setApiKey(_apiKeyController.text.trim());
    await _prefs.setEnabled(_enabled);
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await _service.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSucceeded = ok;
      _testResult = ok
          ? 'Connexion réussie.'
          : 'Échec - vérifie l\'adresse et la clé API.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, const Text('Bazarr')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Recherche directe des sous-titres via Bazarr plutôt que via '
              'Emby - télécharge français et anglais automatiquement, sans '
              'liste à choisir (Bazarr sélectionne lui-même le meilleur '
              'résultat).',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              focusNode: _enabledFocus,
              title: const Text('Activer Bazarr'),
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                unawaited(_save());
              },
            ),
            const SizedBox(height: 8),
            _buildField(
              label: 'Adresse du serveur',
              hint: 'https://bazarr.sidounette.ch',
              controller: _urlController,
              focusNode: _urlFocus,
              tvFieldKey: _urlTvFieldKey,
              onTvKey: _onUrlKey,
              tvType: TextFieldType.url,
            ),
            const SizedBox(height: 12),
            _buildField(
              label: 'Clé API',
              hint: 'Clé API',
              controller: _apiKeyController,
              focusNode: _apiKeyFocus,
              tvFieldKey: _apiKeyTvFieldKey,
              onTvKey: _onApiKeyKey,
              tvType: TextFieldType.password,
              mobileSuffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              focusNode: _testFocus,
              onPressed: _testing ? null : _test,
              child: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tester la connexion'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testSucceeded ? Colors.green : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
