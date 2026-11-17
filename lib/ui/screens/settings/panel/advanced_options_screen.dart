part of '../settings_side_panel.dart';

class _AdvancedOptionsScreen extends StatefulWidget {
  const _AdvancedOptionsScreen();

  @override
  State<_AdvancedOptionsScreen> createState() => _AdvancedOptionsScreenState();
}

class _AdvancedOptionsScreenState extends State<_AdvancedOptionsScreen> {
  final _advancedScope = FocusScopeNode(
    debugLabel: 'AdvancedOptionsSettingsScope',
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );

  @override
  void dispose() {
    _advancedScope.dispose();
    super.dispose();
  }

  Future<void> _clearImageCache(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await clearImageDiskCache();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.imageCacheCleared)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.advancedOptions)),
      body: FocusScope(
        node: _advancedScope,
        autofocus: true,
        child: ListView(
          children: [
            _SectionHeader(l10n.playback),
            adaptiveListSection(
              children: [
                SliderPreferenceTile(
                  preference: UserPreferences.videoStartDelay,
                  title: l10n.settingsVideoStartDelay,
                  icon: Icons.schedule,
                  min: 0,
                  max: 5000,
                  divisions: 20,
                  labelOf: (v) => l10n.settingsMillisecondsValue(v.round()),
                  autofocus: true,
                ),
              ],
            ),
            if (PlatformDetection.isAndroid) ...[
              _SectionHeader(l10n.performanceMode),
              adaptiveListSection(
                children: [
                  EnumPreferenceTile<DevicePerformanceMode>(
                    preference: UserPreferences.performanceMode,
                    title: l10n.performanceMode,
                    description: l10n.performanceModeSubtitle,
                    icon: Icons.speed_outlined,
                    labelOf: (v) => switch (v) {
                      DevicePerformanceMode.auto => l10n.performanceModeAuto,
                      DevicePerformanceMode.standard =>
                        l10n.performanceModeStandard,
                      DevicePerformanceMode.reduced =>
                        l10n.performanceModeReduced,
                    },
                  ),
                ],
              ),
            ],
            // 17.11, Sid : « si tu arrives à me faire fonctionner patounetv
            // en tant que seerr, je prends ». L'app ne savait joindre un
            // service de requêtes qu'à travers le plugin Moonfin du serveur
            // média - un plugin Jellyfin, donc absent de son Emby. Ces trois
            // champs ouvrent la voie directe : l'adresse remplace le chemin
            // du plugin, et les identifiants servent à ouvrir la session
            // (Patoune TV authentifie par session, pas par jeton).
            //
            // Laissés vides, rien ne change : on reste sur le chemin Moonfin
            // d'origine. Voir UserPreferences.seerrDirectApiUrl.
            _SectionHeader(l10n.mediaRequestIntegration),
            adaptiveListSection(
              children: [
                _EditableStringPreferenceTile(
                  preference: UserPreferences.seerrDirectApiUrl,
                  title: l10n.seerrDirectApiUrlTitle,
                  icon: Icons.link,
                  hintText: 'https://exemple.ch/api/jellyseerr/api/v1',
                ),
                _EditableStringPreferenceTile(
                  preference: UserPreferences.seerrDirectEmail,
                  title: l10n.email,
                  icon: Icons.alternate_email,
                  hintText: l10n.email,
                ),
                _EditableStringPreferenceTile(
                  preference: UserPreferences.seerrDirectPassword,
                  title: l10n.password,
                  icon: Icons.key_outlined,
                  hintText: l10n.password,
                ),
              ],
            ),
            // 17.11 : interrupteur de campagne. Allumé le temps d'une chasse
            // au bug, éteint ensuite - d'où un réglage plutôt qu'un bouton
            // permanent dans la barre.
            _SectionHeader(l10n.diagnostics),
            adaptiveListSection(
              children: [
                SwitchPreferenceTile(
                  preference: UserPreferences.showDiagnosticsShortcut,
                  title: l10n.diagnosticsShortcutTitle,
                  subtitle: l10n.diagnosticsShortcutSubtitle,
                  icon: Icons.bug_report_outlined,
                ),
              ],
            ),
            if (!PlatformDetection.isWeb) ...[
              _SectionHeader(l10n.storage),
              adaptiveListSection(
                children: [
                  IntPickerPreferenceTile(
                    preference: UserPreferences.imageCacheLimitMb,
                    title: l10n.imageCacheLimit,
                    icon: Icons.image_outlined,
                    options: {
                      0: l10n.noLimit,
                      100: l10n.mbValue(100),
                      200: l10n.mbValue(200),
                      350: l10n.mbValue(350),
                      500: l10n.mbValue(500),
                      1024: l10n.mbValue(1024),
                      2048: l10n.mbValue(2048),
                    },
                    onChanged: () {
                      final mb = GetIt.instance<UserPreferences>()
                          .get(UserPreferences.imageCacheLimitMb);
                      unawaited(enforceImageCacheBudget(mb * 1024 * 1024));
                    },
                  ),
                  _TvSettingsListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(l10n.clearImageCache),
                    onTap: () => _clearImageCache(context),
                  ),
                ],
              ),
            ],
            if (PlatformDetection.isAndroid) ...[
              _SectionHeader(l10n.playerRouting),
              adaptiveListSection(
                children: [
                  if (PlatformDetection.isTV) ...[
                    SwitchPreferenceTile(
                      preference: UserPreferences.preferExoPlayerFfmpeg,
                      title: l10n.preferSoftwareDecoders,
                      subtitle: l10n.preferSoftwareDecodersSubtitle,
                      icon: Icons.memory,
                    ),
                    SwitchPreferenceTile(
                      preference: UserPreferences.media3SkipSilence,
                      title: l10n.skipSilenceTitle,
                      subtitle: l10n.skipSilenceSubtitle,
                      icon: Icons.graphic_eq,
                    ),
                    SwitchPreferenceTile(
                      preference: UserPreferences.media3AllowExternalAudioEffects,
                      title: l10n.allowExternalAudioEffectsTitle,
                      subtitle: l10n.allowExternalAudioEffectsSubtitle,
                      icon: Icons.equalizer,
                    ),
                    SwitchPreferenceTile(
                      preference: UserPreferences.media3TunnelingDisabled,
                      inverted: true,
                      title: l10n.enableTunnelingTitle,
                      subtitle: l10n.enableTunnelingSubtitle,
                      icon: Icons.tv,
                    ),
                    SwitchPreferenceTile(
                      preference: UserPreferences.media3MapDolbyVisionProfile7ToHevc,
                      title: l10n.mapDolbyVisionP7Title,
                      subtitle: l10n.mapDolbyVisionP7Subtitle,
                      icon: Icons.hdr_strong,
                    ),
                  ],
                  SwitchPreferenceTile(
                    preference: UserPreferences.useExternalPlayer,
                    title: l10n.useExternalPlayer,
                    subtitle: l10n.useExternalPlayerSubtitle,
                    icon: Icons.open_in_new,
                  ),
                  const _ExternalPlayerAppPickerTile(),
                ],
              ),
            ],
            if (!PlatformDetection.isTV &&
                !PlatformDetection.isIOS &&
                !PlatformDetection.isWeb) ...[
              _SectionHeader(l10n.mpvConfiguration),
              adaptiveListSection(
                children: [
                  SwitchPreferenceTile(
                    preference: UserPreferences.customMpvConfEnabled,
                    title: l10n.enableCustomMpvConf,
                    subtitle: l10n.applyMpvConfBeforePlayback,
                    icon: Icons.tune,
                  ),
                  _EditableStringPreferenceTile(
                    preference: UserPreferences.customMpvConfPath,
                    title: l10n.customMpvConfPath,
                    icon: Icons.description,
                    hintText: l10n.pathToMpvConf,
                    pickPath: () async {
                      String? initialDir;
                      try {
                        initialDir =
                            (await getApplicationSupportDirectory()).path;
                      } catch (_) {}
                      final result = await FilePicker.pickFiles(
                        dialogTitle: l10n.selectMpvConf,
                        initialDirectory: initialDir,
                      );
                      return result?.files.single.path;
                    },
                  ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.customMpvConfUnsafeAdvanced,
                    title: l10n.unsafeAdvancedMpvOptions,
                    subtitle: l10n.unsafeMpvOptionsDescription,
                    icon: Icons.warning_amber,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
