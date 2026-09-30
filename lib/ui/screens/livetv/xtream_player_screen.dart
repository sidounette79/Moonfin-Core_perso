import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/channel_group.dart';
import '../../../data/models/playable_channel.dart';
import '../../screensaver/screensaver_controller.dart';

/// 30.09, Sid: "un truc complet qui marche bien" - direct IPTV playback
/// with channel zapping and a short EPG overlay, visually mirroring the
/// Emby Live TV player's zap/OSD pattern (left/right zaps only while the
/// OSD is hidden - same rule, see live_tv_player_screen.dart) but backed
/// by media_kit directly instead of PlaybackManager, since these channels
/// have no corresponding Emby item for the manager to resolve - same
/// engine TrailerPlayerScreen already proves works for a raw stream URL.
/// Takes PlayableChannel (not a raw XtreamChannel) so it works the same
/// whether a channel came from Xtream Codes or a plain M3U playlist.
class XtreamPlayerScreen extends StatefulWidget {
  final List<PlayableChannel> channels;
  final int initialIndex;

  const XtreamPlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
  });

  @override
  State<XtreamPlayerScreen> createState() => _XtreamPlayerScreenState();
}

class _XtreamPlayerScreenState extends State<XtreamPlayerScreen> {
  static const _openTimeout = Duration(seconds: 12);
  static const _osdAutoHideDelay = Duration(seconds: 5);

  // 30.09, Sid: "Smart Channels" - when the same channel is configured
  // across more than one provider, a stall this long tries the next
  // source instead of just sitting there buffering. Longer than
  // clubTivi's own 3s default (github.com/clubanderson/clubTivi, Apache
  // 2.0 - see THIRD_PARTY_NOTICES.md): IPTV streams here see brief,
  // self-resolving rebuffers often enough that 3s would fail over on
  // plenty of stalls that were about to recover on their own.
  static const _stallThreshold = Duration(seconds: 8);
  static const _maxFailoverAttempts = 3;

  final _screensaverController = GetIt.instance<ScreensaverController>();
  final _focusNode = FocusNode(debugLabel: 'xtreamPlayer');

  Player? _player;
  VideoController? _controller;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;

  late int _currentIndex = widget.initialIndex;
  bool _loading = true;
  bool _buffering = false;
  String? _error;
  bool _osdVisible = true;
  Timer? _osdHideTimer;
  List<EpgEntryData> _epg = const [];
  int _openToken = 0;

  late final List<ChannelGroup> _groups = ChannelGroup.groupChannels(
    widget.channels,
  );
  Timer? _stallTimer;
  int _alternativeIndex = 0;
  int _failoverAttempts = 0;

  PlayableChannel get _current => widget.channels[_currentIndex];

  ChannelGroup _groupFor(PlayableChannel channel) => _groups.firstWhere(
    (g) => g.alternatives.contains(channel),
    orElse: () => ChannelGroup(key: '', alternatives: [channel]),
  );

  /// The source actually feeding the player right now - [_current] unless
  /// a Smart Channels failover has switched to one of its alternatives.
  PlayableChannel get _activeSource {
    final group = _groupFor(_current);
    if (_alternativeIndex >= group.alternatives.length) return _current;
    return group.alternatives[_alternativeIndex];
  }

  @override
  void initState() {
    super.initState();
    _screensaverController.setPlaybackActive(true);
    _player = Player(configuration: const PlayerConfiguration(libass: false));
    _controller = VideoController(_player!);
    _bufferingSub = _player!.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
      if (b) {
        _stallTimer ??= Timer(_stallThreshold, _tryFailover);
      } else {
        _stallTimer?.cancel();
        _stallTimer = null;
        _failoverAttempts = 0;
      }
    });
    _errorSub = _player!.stream.error.listen((message) {
      if (!mounted) return;
      final group = _groupFor(_current);
      if (group.alternatives.length > 1 &&
          _failoverAttempts < _maxFailoverAttempts) {
        unawaited(_tryFailover());
        return;
      }
      setState(() {
        _loading = false;
        _error = message;
      });
    });
    unawaited(_openChannel(_currentIndex));
    _scheduleOsdAutoHide();
  }

  @override
  void dispose() {
    _osdHideTimer?.cancel();
    _stallTimer?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _screensaverController.setPlaybackActive(false);
    _focusNode.dispose();
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  void _scheduleOsdAutoHide() {
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(_osdAutoHideDelay, () {
      if (mounted) setState(() => _osdVisible = false);
    });
  }

  void _showOsd() {
    setState(() => _osdVisible = true);
    _scheduleOsdAutoHide();
  }

  Future<void> _openChannel(int index) async {
    final token = ++_openToken;
    _stallTimer?.cancel();
    _stallTimer = null;
    _alternativeIndex = 0;
    _failoverAttempts = 0;
    setState(() {
      _currentIndex = index;
      _loading = true;
      _error = null;
      _epg = const [];
    });

    final entry = _current;
    final url = entry.streamUrl;

    try {
      await _player!.open(Media(url)).timeout(_openTimeout);
      if (!mounted || token != _openToken) return;
      setState(() => _loading = false);
    } on TimeoutException {
      if (!mounted || token != _openToken) return;
      if (await _tryFailover()) return;
      if (!mounted || token != _openToken) return;
      setState(() {
        _loading = false;
        _error = 'La chaîne ne répond pas (délai dépassé)';
      });
    } catch (e) {
      if (!mounted || token != _openToken) return;
      if (await _tryFailover()) return;
      if (!mounted || token != _openToken) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de lire cette chaîne';
      });
    }

    unawaited(_loadEpg(token));
  }

  /// Tries the next source configured for this same logical channel (see
  /// ChannelGroup), round-robin, up to [_maxFailoverAttempts] - called
  /// after [_stallThreshold] of continuous buffering, on a hard player
  /// error, or when opening a source times out/throws. Leaves
  /// _currentIndex and the EPG alone: from the viewer's side this is still
  /// the same channel, just a different source under it. A no-op (falls
  /// through to whatever the caller does when this returns false) once
  /// there's only one source or attempts are spent.
  Future<bool> _tryFailover() async {
    _stallTimer = null;
    if (!mounted) return false;

    final group = _groupFor(_current);
    if (group.alternatives.length <= 1) return false;
    if (_failoverAttempts >= _maxFailoverAttempts) return false;
    _failoverAttempts++;
    _alternativeIndex = (_alternativeIndex + 1) % group.alternatives.length;
    final source = group.alternatives[_alternativeIndex];

    final token = ++_openToken;
    try {
      await _player!.open(Media(source.streamUrl)).timeout(_openTimeout);
    } catch (_) {
      // Opening this alternative itself failed/timed out - treat it the
      // same as a stall on it and keep going below.
    }
    if (!mounted || token != _openToken) return true;

    // media_kit's buffering stream only fires on a real transition, and it
    // can easily stay continuously true across the open() above (still
    // buffering on the new source) - nothing would toggle it false-then-
    // true again to re-arm the listener's own timer, so this re-arms
    // itself directly whenever there are attempts left to spend.
    if (_buffering && _failoverAttempts < _maxFailoverAttempts) {
      _stallTimer = Timer(_stallThreshold, _tryFailover);
    }
    return true;
  }

  Future<void> _loadEpg(int token) async {
    final fetchEpg = _current.fetchEpg;
    if (fetchEpg == null) return;
    final listings = await fetchEpg();
    if (!mounted || token != _openToken) return;
    setState(() => _epg = listings);
  }

  Future<void> _zap(int delta) async {
    final count = widget.channels.length;
    if (count <= 1) return;
    final newIndex = (_currentIndex + delta) % count;
    await _openChannel(newIndex < 0 ? newIndex + count : newIndex);
    _scheduleOsdAutoHide();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    // Left/right zaps only while the OSD is hidden - matching the Emby
    // Live TV player's own rule (see live_tv_player_screen.dart) so
    // left/right keeps its normal role of moving between OSD controls
    // once it's up.
    if (!_osdVisible &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      unawaited(_zap(key == LogicalKeyboardKey.arrowRight ? 1 : -1));
      return KeyEventResult.handled;
    }

    if (!_osdVisible) {
      _showOsd();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _showOsd();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Widget _buildOsd() {
    final entry = _current;
    final now = DateTime.now();
    final current = _epg.isEmpty
        ? null
        : _epg.firstWhere(
            (e) => now.isAfter(e.start) && now.isBefore(e.end),
            orElse: () => _epg.first,
          );

    return AnimatedOpacity(
      opacity: _osdVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_osdVisible,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.transparent,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          alignment: Alignment.bottomLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // Not just entry.sourceName: after a Smart Channels
                // failover this channel is still `entry`, but the stream
                // actually playing is a different source's copy of it -
                // showing the original would be a straight-up lie about
                // what's on screen right now.
                _activeSource.sourceName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              if (current != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${_formatTime(current.start)} - ${_formatTime(current.end)}  ${current.title}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Colors.white, size: 36),
                    onPressed: () => _zap(-1),
                  ),
                  Text(
                    '${_currentIndex + 1} / ${widget.channels.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right,
                        color: Colors.white, size: 36),
                    onPressed: () => _zap(1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _osdVisible ? _scheduleOsdAutoHide() : _showOsd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null)
                Video(controller: _controller!, controls: NoVideoControls),
              if (_loading || _buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => _openChannel(_currentIndex),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildOsd(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
