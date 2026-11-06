part of '../settings_side_panel.dart';

/// Which tabs sit between Home and You on the mobile bottom navbar. Until the
/// user pins something the bar picks them from the nav button switches, and
/// this screen shows that choice as the starting point.
class _BottomNavTabsScreen extends StatefulWidget {
  const _BottomNavTabsScreen();

  @override
  State<_BottomNavTabsScreen> createState() => _BottomNavTabsScreenState();
}

class _BottomNavTabsScreenState extends State<_BottomNavTabsScreen> {
  final _prefs = GetIt.instance<UserPreferences>();

  BottomNavTabGates get _gates => BottomNavTabGates.fromPreferences(
        _prefs,
        seerrAvailable: GetIt.instance<PluginSyncService>().seerrAvailable,
      );

  String get _raw => _prefs.get(UserPreferences.bottomNavbarTabs);
  bool get _automatic => isAutomaticBottomNavTabs(_raw);

  // 06.11, Sid ("et pouvoir en épingler plus que 3 - me laisser le
  // choix"): was a fixed constant, now a profile preference clamped to
  // the picker's ceiling.
  int get _maxPins => _prefs
      .get(UserPreferences.maxPinnedBottomNavTabs)
      .clamp(1, kMaxPinnedBottomNavTabsCeiling);

  // Explicit pins are listed even when their switch is off, so the user can
  // see why a tab went missing from the bar.
  List<BottomNavTab> get _pinned => _automatic
      ? _gates.resolvePins(_raw, maxPins: _maxPins)
      : parsePinnedBottomNavTabs(_raw, maxPins: _maxPins);

  Future<void> _write(List<BottomNavTab> pins) async {
    await _prefs.set(
      UserPreferences.bottomNavbarTabs,
      serializePinnedBottomNavTabs(pins, maxPins: _maxPins),
    );
    _pushPersonalizationSync();
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    await _prefs.removePreference(UserPreferences.bottomNavbarTabs);
    _pushPersonalizationSync();
    if (mounted) setState(() {});
  }

  Future<void> _setMaxPins(int value) async {
    await _prefs.set(UserPreferences.maxPinnedBottomNavTabs, value);
    // A lower ceiling can leave more pins than it now allows - trim rather
    // than silently ignore the overflow next time the bar reads them.
    final current = _pinned;
    if (current.length > value) {
      await _prefs.set(
        UserPreferences.bottomNavbarTabs,
        serializePinnedBottomNavTabs(current, maxPins: value),
      );
    }
    _pushPersonalizationSync();
    if (mounted) setState(() {});
  }

  void _move(List<BottomNavTab> pins, int from, int to) {
    final next = [...pins];
    next.insert(to, next.removeAt(from));
    _write(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final gates = _gates;
    final pinned = _pinned;
    final maxPins = _maxPins;
    final full = pinned.length >= maxPins;
    final split = _prefs.get(UserPreferences.bottomNavbarStyle) ==
        BottomNavbarStyle.split;

    Widget icon(BottomNavTab tab, {required bool enabled}) =>
        bottomNavTabIconWidget(
          tab,
          active: false,
          size: 24,
          color: enabled
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: 0.38),
        );

    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.bottomNavbarTabs)),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l10n.bottomNavbarTabsDescription, style: hint),
            ),
            if (split)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(l10n.bottomNavbarSplitSearchNote, style: hint),
              ),
            // 06.11, Sid ("et pouvoir en épingler plus que 3 - me laisser
            // le choix"): a plain stepper rather than IntPickerPreferenceTile
            // - lowering the max has to trim any pins that no longer fit
            // (_setMaxPins), which that tile's onChanged (no new value
            // passed) can't drive cleanly.
            adaptiveListSection(
              children: [
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(l10n.bottomNavbarTabsMaxPins),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: maxPins <= 1
                            ? null
                            : () => _setMaxPins(maxPins - 1),
                      ),
                      Text(
                        '$maxPins',
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: maxPins >= kMaxPinnedBottomNavTabsCeiling
                            ? null
                            : () => _setMaxPins(maxPins + 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _SectionHeader(
              _automatic
                  ? '${l10n.bottomNavbarTabsPinned} · '
                      '${l10n.bottomNavbarTabsAutomatic}'
                  : l10n.bottomNavbarTabsPinned,
            ),
            adaptiveListSection(
              children: [
                for (var i = 0; i < pinned.length; i++)
                  ListTile(
                    leading: icon(pinned[i], enabled: gates.offers(pinned[i])),
                    title: Text(bottomNavTabLabel(l10n, pinned[i])),
                    subtitle: gates.offers(pinned[i])
                        ? null
                        : Text(l10n.bottomNavbarTabTurnedOff),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.moveUp,
                          icon: const Icon(Icons.keyboard_arrow_up),
                          onPressed: i == 0
                              ? null
                              : () => _move(pinned, i, i - 1),
                        ),
                        IconButton(
                          tooltip: l10n.moveDown,
                          icon: const Icon(Icons.keyboard_arrow_down),
                          onPressed: i == pinned.length - 1
                              ? null
                              : () => _move(pinned, i, i + 1),
                        ),
                        // The bar always keeps one tab between Home and You.
                        IconButton(
                          tooltip: l10n.remove,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: pinned.length <= 1
                              ? null
                              : () => _write([...pinned]..removeAt(i)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _SectionHeader(l10n.bottomNavbarTabsAvailable),
            if (full)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.bottomNavbarTabsLimit, style: hint),
              ),
            adaptiveListSection(
              children: [
                for (final tab in BottomNavTab.values)
                  if (!pinned.contains(tab))
                    ListTile(
                      enabled: gates.offers(tab) && !full,
                      leading: icon(tab, enabled: gates.offers(tab) && !full),
                      title: Text(bottomNavTabLabel(l10n, tab)),
                      subtitle: gates.offers(tab)
                          ? null
                          : Text(l10n.bottomNavbarTabTurnedOff),
                      trailing: const Icon(Icons.push_pin_outlined),
                      onTap: () => _write([...pinned, tab]),
                    ),
              ],
            ),
            if (!_automatic)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.bottomNavbarTabsReset),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
