part of '../settings_side_panel.dart';

class _AboutCategoryScreen extends StatelessWidget {
  const _AboutCategoryScreen();

  @override
  Widget build(BuildContext context) {
    final appVersion = AppBeta.label(GetIt.instance<DeviceInfo>().appVersion);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Image.asset('assets/images/carba_tv_logo.png', height: 72),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.versionValue(appVersion),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          _SectionHeader(l10n.settingsAppInfo),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.version),
                subtitle: Text(appVersion),
                trailing: const SizedBox.shrink(),
                onTap: () {},
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.system_update_alt),
                title: Text(l10n.settingsCheckForOtaPatch),
                subtitle: Text(l10n.settingsCheckForOtaPatchSubtitleNoPatch),
                onTap: () => context.pushSettingsScreen(const OtaPatchScreen()),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.troubleshoot),
                title: const Text('Diagnostics & Logging'),
                subtitle: const Text(
                  'Capture media, login and network logs and send them to the '
                  'server as a report',
                ),
                onTap: () => context.pushSettingsScreen(
                  const DiagnosticsSettingsScreen(),
                ),
              ),
              if (PlatformDetection.useDesktopUi)
                _TvSettingsListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(l10n.keyboardShortcutsTitle),
                  subtitle: Text(l10n.keyboardShortcutsSubtitle),
                  onTap: () => context.pushSettingsScreen(
                    const _KeyboardShortcutsScreen(),
                  ),
                ),
              _TvSettingsListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(l10n.runSetupAgain),
                // Asking again on purpose says more than the stored answers do,
                // so a deliberate re-run offers every question back.
                onTap: () {
                  GetIt.instance<SetupWizardGate>().beginRerun();
                  context.navigateTopLevel(Destinations.setup);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
