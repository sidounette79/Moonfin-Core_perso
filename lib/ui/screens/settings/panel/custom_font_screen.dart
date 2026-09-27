part of '../settings_side_panel.dart';

// 27.09, Sid: "ajouter ta propre police comme asset et un petit sélecteur
// dédié" - standalone font choice, independent of the visual theme picker
// (appearance_theme_screen.dart). Overrides every theme's own font when
// set to anything but "Thème par défaut" - see AppTheme._effectiveFontFamily.
class _CustomFontScreen extends StatefulWidget {
  const _CustomFontScreen();

  @override
  State<_CustomFontScreen> createState() => _CustomFontScreenState();
}

class _CustomFontScreenState extends State<_CustomFontScreen> {
  final _prefs = GetIt.instance<UserPreferences>();

  static const _previewText = 'Pooky Music, CARBA TV, Moonfin';

  String _fontLabel(CustomFontFamily value) => switch (value) {
        CustomFontFamily.themeDefault => 'Thème par défaut',
        CustomFontFamily.inter => 'Inter',
        CustomFontFamily.poppins => 'Poppins',
        CustomFontFamily.montserrat => 'Montserrat',
        CustomFontFamily.nunito => 'Nunito',
        CustomFontFamily.spaceGrotesk => 'Space Grotesk',
      };

  String? _fontFamilyName(CustomFontFamily value) => switch (value) {
        CustomFontFamily.themeDefault => null,
        CustomFontFamily.inter => 'CustomFontInter',
        CustomFontFamily.poppins => 'CustomFontPoppins',
        CustomFontFamily.montserrat => 'CustomFontMontserrat',
        CustomFontFamily.nunito => 'CustomFontNunito',
        CustomFontFamily.spaceGrotesk => 'CustomFontSpaceGrotesk',
      };

  @override
  Widget build(BuildContext context) {
    final current = _prefs.get(UserPreferences.customFontFamily);
    return Scaffold(
      appBar: buildSettingsAppBar(context, const Text('Police')),
      body: ListView(
        children: [
          _SectionHeader('Police de l\'interface'),
          adaptiveListSection(
            children: [
              EnumPreferenceTile<CustomFontFamily>(
                preference: UserPreferences.customFontFamily,
                title: 'Police',
                icon: Icons.text_fields,
                autofocus: true,
                onChanged: () {
                  setState(() {});
                  AppThemeScope.of(context).refreshVisualOverrides();
                },
                labelOf: _fontLabel,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aperçu',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _previewText,
                      style: TextStyle(
                        fontFamily: _fontFamilyName(current),
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
