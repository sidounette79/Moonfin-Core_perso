import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../data/services/socket_handler.dart';
import '../../l10n/app_localizations.dart';
import '../util/error_message.dart';
import 'bounded_network_image.dart';

// 06.11, Sid ("remplacer ma remote home assistant" / "un onglet purement
// telecommande"): session polling + GeneralCommand/PlayState plumbing and
// the D-pad/transport/volume controls used to live only in
// remote_control_dialog.dart (the bottom-sheet "Télécommande" reachable
// from the account menu). A second presentation - a full screen with a
// fixed 3-TV quick selector instead of the full session list - needs the
// exact same logic and the exact same controls, just a different header
// and container. Extracted here rather than duplicated: this is real
// shared behaviour between two screens, not a speculative abstraction.
mixin RemoteControlSessionMixin<T extends StatefulWidget> on State<T> {
  late final SessionApi sessionApi;
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;
  bool fetching = false;
  String? error;
  Map<String, dynamic>? selectedSession;
  bool busy = false;
  double? seekPosition;
  double? volume;
  String? volumeSessionId;
  Timer? _refreshTimer;
  StreamSubscription<ServerWebSocketMessage>? _socketSub;

  void initRemoteControlSession() {
    sessionApi = GetIt.instance<MediaServerClient>().sessionApi;
    loadSessions();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refreshSessions(),
    );
    _socketSub = GetIt.instance<SocketHandler>().events.listen((event) {
      switch (event) {
        case SessionEndedMessage():
        case PlayMessage():
        case PlaystateMessage():
        case GeneralCommandMessage():
          refreshSessions();
        case ServerEventMessage(:final type)
            when type == 'SessionsStart' || type == 'SessionsStop':
          refreshSessions();
        default:
          break;
      }
    });
  }

  void disposeRemoteControlSession() {
    _socketSub?.cancel();
    _refreshTimer?.cancel();
  }

  Future<void> loadSessions() async {
    if (fetching) return;
    fetching = true;
    try {
      final client = GetIt.instance<MediaServerClient>();
      List<Map<String, dynamic>> strictSessions = const [];
      try {
        strictSessions = await sessionApi.getSessions(
          controllableByUserId: client.userId,
        );
      } catch (_) {}

      List<Map<String, dynamic>> fallbackSessions = const [];
      if (strictSessions.isEmpty) {
        try {
          fallbackSessions = await sessionApi.getSessions();
        } catch (_) {}
      }

      final merged = _mergeUniqueSessions([
        ...strictSessions,
        ...fallbackSessions,
      ]);
      if (!mounted) return;
      final selfDeviceId = client.deviceInfo.id;
      final controllable = merged.where((s) {
        final deviceId = s['DeviceId']?.toString();
        if (deviceId != null && deviceId == selfDeviceId) {
          return false;
        }
        return _isPotentiallyControllable(s);
      }).toList();
      setState(() {
        sessions = controllable;
        loading = false;
        error = null;
        if (selectedSession != null) {
          final id = selectedSession!['Id'];
          selectedSession = controllable
              .cast<Map<String, dynamic>?>()
              .firstWhere((s) => s?['Id'] == id, orElse: () => null);
        }
        reconcileVolume();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = describeError(e, AppLocalizations.of(context));
        loading = false;
      });
    } finally {
      fetching = false;
    }
  }

  List<Map<String, dynamic>> _mergeUniqueSessions(
    List<Map<String, dynamic>> input,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final session in input) {
      final id = session['Id']?.toString();
      if (id == null || id.isEmpty) continue;
      byId.putIfAbsent(id, () => session);
    }
    return byId.values.toList();
  }

  bool _isPotentiallyControllable(Map<String, dynamic> session) {
    final supportsRemote = session['SupportsRemoteControl'];
    if (supportsRemote is bool && supportsRemote) return true;
    final supportsMedia = session['SupportsMediaControl'];
    if (supportsMedia is bool && supportsMedia) return true;
    final commands = session['SupportedCommands'];
    if (commands is List) return commands.whereType<String>().isNotEmpty;
    return false;
  }

  Future<void> refreshSessions() async {
    if (fetching) return;
    await loadSessions();
  }

  void selectSession(Map<String, dynamic>? session) {
    setState(() {
      selectedSession = session;
      // Another device has its own volume and position, so what was held
      // for the last one doesn't carry over.
      volume = null;
      volumeSessionId = null;
      seekPosition = null;
    });
  }

  Future<void> runCommand(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await Future.delayed(const Duration(milliseconds: 300));
      await refreshSessions();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.remoteCommandFailed(describeError(e, l10n))),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendPlayState(String command, {int? seekTicks}) {
    final id = selectedSession?['Id']?.toString();
    if (id == null) return Future.value();
    return runCommand(
      () => sessionApi.sendPlayStateCommand(
        id,
        command,
        seekPositionTicks: seekTicks,
      ),
    );
  }

  Future<void> sendGeneral(String commandName, {Map<String, String>? args}) {
    final id = selectedSession?['Id']?.toString();
    if (id == null) return Future.value();
    return runCommand(
      () => sessionApi.sendGeneralCommand(id, commandName, arguments: args),
    );
  }

  /// Hands the slider back to the session once it reports a volume close to
  /// the one we asked for. A session that reports none keeps our value, since
  /// it is the only number either side knows. Called inside a setState.
  void reconcileVolume() {
    final held = volume;
    if (held == null) return;
    final currentId = selectedSession?['Id']?.toString();
    if (currentId == null || currentId != volumeSessionId) {
      volume = null;
      volumeSessionId = null;
      return;
    }
    final playState = selectedSession?['PlayState'] as Map<String, dynamic>?;
    final reported = (playState?['VolumeLevel'] as num?)?.toDouble();
    if (reported != null && (reported - held).abs() <= 2) {
      volume = null;
      volumeSessionId = null;
    }
  }

  bool supportsCommand(Map<String, dynamic> session, String command) {
    final commands = session['SupportedCommands'];
    return commands is List && commands.whereType<String>().contains(command);
  }

  String? posterUrlFor(Map<String, dynamic> nowPlaying) {
    final id = nowPlaying['Id']?.toString();
    if (id == null || id.isEmpty) return null;
    return GetIt.instance<MediaServerClient>().imageApi.getPrimaryImageUrl(
      id,
      maxHeight: 300,
    );
  }

  Widget platformIcon(String client, ThemeData theme) {
    final lc = client.toLowerCase();
    final IconData icon;
    if (lc.contains('android tv') ||
        lc.contains('fire tv') ||
        lc.contains('apple tv') ||
        lc.contains('roku')) {
      icon = Icons.tv;
    } else if (lc.contains('android')) {
      icon = Icons.android;
    } else if (lc.contains('ios') ||
        lc.contains('iphone') ||
        lc.contains('ipad') ||
        lc.contains('apple')) {
      icon = Icons.phone_iphone;
    } else if (lc.contains('web') || lc.contains('browser')) {
      icon = Icons.language;
    } else {
      icon = Icons.devices_other;
    }
    return Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant);
  }

  bool isTvClient(Map<String, dynamic> session) {
    final client = (session['Client'] as String? ?? '').toLowerCase();
    return client.contains('android tv') ||
        client.contains('fire tv') ||
        client.contains('apple tv') ||
        client.contains('roku');
  }

  String _ticksToTime(int ticks) {
    final duration = Duration(microseconds: ticks ~/ 10);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // Shared control block (now-playing card, transport, volume, D-pad, stop)
  // for whichever session is currently selected. Empty when none is.
  List<Widget> buildRemoteControls(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final session = selectedSession;
    if (session == null) return const [];
    final nowPlaying = session['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = session['PlayState'] as Map<String, dynamic>?;
    final isPaused = playState?['IsPaused'] as bool? ?? false;
    final isMuted = playState?['IsMuted'] as bool? ?? false;
    final positionTicks = (playState?['PositionTicks'] as num?)?.toInt();
    final runtimeTicks = (nowPlaying?['RunTimeTicks'] as num?)?.toInt();
    final volumeLevel = (playState?['VolumeLevel'] as num?)?.toDouble();
    final supportsSetVolume = supportsCommand(session, 'SetVolume');

    // 06.11, Sid ("ça viendrait remplacer ma remote home assistant") -
    // unlike the playback transport row below, D-pad navigation has to
    // work even when nothing is currently playing (navigating CarbaTV's
    // own menus from the couch is exactly the case HA's remote covers
    // today). Same MoveUp/MoveDown/MoveLeft/MoveRight/Select/Back/GoHome
    // GeneralCommand names the receiving side already handles - see
    // session_repository.dart's _handleGeneralCommandMessage, wired in
    // since this feature's original "remote control" commit - only the
    // buttons to send them were missing.
    if (nowPlaying == null) {
      return [
        _buildDpad(theme, l10n),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.tv_off, size: 40, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text(
                  l10n.remoteNothingPlaying,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      _buildNowPlayingCard(theme, nowPlaying, positionTicks, runtimeTicks),
      const SizedBox(height: 18),
      _buildTransportRow(theme, isPaused),
      const SizedBox(height: 18),
      _buildVolumeRow(theme, l10n, isMuted, volumeLevel, supportsSetVolume),
      const SizedBox(height: 18),
      _buildDpad(theme, l10n),
      const SizedBox(height: 14),
      _buildStopButton(theme, l10n),
    ];
  }

  Widget _buildDpad(ThemeData theme, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RemoteControlButton(
          icon: Icons.home_rounded,
          label: l10n.home,
          onTap: () => sendGeneral('GoHome'),
        ),
        // 06.11, Sid ("un vrai carré avec les mouvements au doigts... si
        // mon doigt va à droite, ca decale la cellule vers la droite"):
        // one swipe = one step, not a continuous drag repeating MoveUp/
        // etc. while the finger moves - see RemoteSwipePad.
        RemoteSwipePad(
          onSwipe: (direction) => sendGeneral(switch (direction) {
            _SwipeDirection.up => 'MoveUp',
            _SwipeDirection.down => 'MoveDown',
            _SwipeDirection.left => 'MoveLeft',
            _SwipeDirection.right => 'MoveRight',
          }),
          onTap: () => sendGeneral('Select'),
        ),
        RemoteControlButton(
          icon: Icons.arrow_back_rounded,
          label: l10n.back,
          onTap: () => sendGeneral('Back'),
        ),
      ],
    );
  }

  Widget _buildNowPlayingCard(
    ThemeData theme,
    Map<String, dynamic> nowPlaying,
    int? positionTicks,
    int? runtimeTicks,
  ) {
    final title = nowPlaying['Name'] as String? ?? '';
    final series = nowPlaying['SeriesName'] as String?;
    final year = (nowPlaying['ProductionYear'] as num?)?.toInt();
    final subtitle = series ?? (year != null ? '$year' : null);
    final posterUrl = posterUrlFor(nowPlaying);
    final hasSeek =
        positionTicks != null && runtimeTicks != null && runtimeTicks > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: AppRadius.circular(16),
        border: Border.fromBorderSide(ThemeRegistry.active.borders.chipBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 84,
              child: posterUrl == null
                  ? _posterPlaceholder(theme)
                  : BoundedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _posterPlaceholder(theme),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                if (hasSeek) _buildSeekBar(theme, positionTicks, runtimeTicks),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        color: theme.colorScheme.outline,
        size: 24,
      ),
    );
  }

  Widget _buildSeekBar(ThemeData theme, int positionTicks, int runtimeTicks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            padding: EdgeInsets.zero,
          ),
          child: Slider(
            value: (seekPosition ?? positionTicks / runtimeTicks)
                .clamp(0.0, 1.0),
            onChanged: (v) => setState(() => seekPosition = v),
            onChangeEnd: (v) {
              final target = (v * runtimeTicks).round();
              seekPosition = null;
              sendPlayState('Seek', seekTicks: target);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_ticksToTime(positionTicks), style: theme.textTheme.labelSmall),
            Text(_ticksToTime(runtimeTicks), style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }

  Widget _buildTransportRow(ThemeData theme, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RemoteTransportButton(
          icon: Icons.skip_previous_rounded,
          onTap: () => sendPlayState('PreviousTrack'),
        ),
        const SizedBox(width: 18),
        RemoteTransportButton(
          icon: Icons.replay_10_rounded,
          onTap: () => sendPlayState('Rewind'),
        ),
        const SizedBox(width: 18),
        RemotePrimaryTransportButton(
          icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          onTap: () => sendPlayState('PlayPause'),
        ),
        const SizedBox(width: 18),
        RemoteTransportButton(
          icon: Icons.forward_10_rounded,
          onTap: () => sendPlayState('FastForward'),
        ),
        const SizedBox(width: 18),
        RemoteTransportButton(
          icon: Icons.skip_next_rounded,
          onTap: () => sendPlayState('NextTrack'),
        ),
      ],
    );
  }

  Widget _buildVolumeRow(
    ThemeData theme,
    AppLocalizations l10n,
    bool isMuted,
    double? volumeLevel,
    bool supportsSetVolume,
  ) {
    if (!supportsSetVolume) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RemoteControlButton(
            icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            label: isMuted ? l10n.unmute : l10n.mute,
            onTap: () => sendGeneral(isMuted ? 'Unmute' : 'Mute'),
          ),
          const SizedBox(width: 8),
          RemoteControlButton(
            icon: Icons.volume_down_rounded,
            label: l10n.sessionVolumeDown,
            onTap: () => sendGeneral('VolumeDown'),
          ),
          const SizedBox(width: 8),
          RemoteControlButton(
            icon: Icons.volume_up_rounded,
            label: l10n.sessionVolumeUp,
            onTap: () => sendGeneral('VolumeUp'),
          ),
        ],
      );
    }

    final value = (volume ?? volumeLevel ?? 100).clamp(0.0, 100.0);
    final IconData volumeIcon;
    if (isMuted || value == 0) {
      volumeIcon = Icons.volume_off_rounded;
    } else if (value < 50) {
      volumeIcon = Icons.volume_down_rounded;
    } else {
      volumeIcon = Icons.volume_up_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.circular(14),
        border: Border.fromBorderSide(ThemeRegistry.active.borders.chipBorder),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(volumeIcon),
            color: theme.colorScheme.onSurfaceVariant,
            tooltip: isMuted ? l10n.unmute : l10n.mute,
            onPressed: () => sendGeneral(isMuted ? 'Unmute' : 'Mute'),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                min: 0,
                max: 100,
                value: value,
                onChanged: (v) => setState(() => volume = v),
                onChangeEnd: (v) {
                  // The value has to stay put until the session reports one of
                  // its own. Most never report a volume at all, so dropping it
                  // here leaves the slider on its fallback of 100.
                  setState(() {
                    volume = v;
                    volumeSessionId = selectedSession?['Id']?.toString();
                  });
                  sendGeneral('SetVolume', args: {'Volume': v.round().toString()});
                },
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${value.round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopButton(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: TextButton.icon(
        onPressed: () => sendPlayState('Stop'),
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: Text(l10n.stop),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

class RemoteControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const RemoteControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: fg),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class RemoteTransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const RemoteTransportButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 28, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class RemotePrimaryTransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const RemotePrimaryTransportButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 32, color: theme.colorScheme.onPrimary),
        ),
      ),
    );
  }
}

enum _SwipeDirection { up, down, left, right }

// 06.11, Sid ("un vrai carré avec les mouvements au doigts... si mon doigt
// va à droite, ca decale la cellule vers la droite"): one discrete swipe
// = one MoveUp/Down/Left/Right, same as a real Android TV remote's
// trackpad in practice - not a continuous drag repeating the command
// while the finger moves (the API only has discrete steps, no absolute
// cursor position to track). A short tap (below the swipe threshold)
// selects instead, same as tapping a real trackpad.
class RemoteSwipePad extends StatefulWidget {
  final ValueChanged<_SwipeDirection> onSwipe;
  final VoidCallback onTap;

  const RemoteSwipePad({
    super.key,
    required this.onSwipe,
    required this.onTap,
  });

  @override
  State<RemoteSwipePad> createState() => _RemoteSwipePadState();
}

class _RemoteSwipePadState extends State<RemoteSwipePad> {
  Offset _dragTotal = Offset.zero;

  // Below this many logical pixels of total movement, a gesture is a tap
  // (a perfectly still finger lifting off a touchscreen is rare), not an
  // attempted swipe.
  static const double _swipeThreshold = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onPanStart: (_) => _dragTotal = Offset.zero,
      onPanUpdate: (details) => _dragTotal += details.delta,
      onPanEnd: (_) {
        final dx = _dragTotal.dx;
        final dy = _dragTotal.dy;
        if (dx.abs() < _swipeThreshold && dy.abs() < _swipeThreshold) {
          widget.onTap();
          return;
        }
        widget.onSwipe(
          dx.abs() > dy.abs()
              ? (dx > 0 ? _SwipeDirection.right : _SwipeDirection.left)
              : (dy > 0 ? _SwipeDirection.down : _SwipeDirection.up),
        );
      },
      child: Container(
        width: 148,
        height: 148,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: AppRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: Icon(
            Icons.check_rounded,
            size: 32,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
