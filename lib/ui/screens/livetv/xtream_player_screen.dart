import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/playable_channel.dart';
import '../../../data/services/iptv_player_service.dart';
import '../../screensaver/screensaver_controller.dart';

/// 30.09, Sid: "un truc complet qui marche bien" - direct IPTV playback
/// with channel zapping and a short EPG overlay, visually mirroring the
/// Emby Live TV player's zap/OSD pattern (left/right zaps only while the
/// OSD is hidden - same rule, see live_tv_player_screen.dart).
///
/// 01.10: no longer owns its own media_kit Player - playback itself
/// (open/zap/failover/EPG) now lives in the shared IptvPlayerService so the
/// same stream keeps playing uninterrupted when this screen is pushed on
/// top of (or popped back to) the channels screen's own mini preview; this
/// screen is just the fullscreen chrome (OSD, zap keys, back button) around
/// whatever the service is already showing.
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
  static const _osdAutoHideDelay = Duration(seconds: 5);

  final _service = GetIt.instance<IptvPlayerService>();
  final _screensaverController = GetIt.instance<ScreensaverController>();
  final _focusNode = FocusNode(debugLabel: 'xtreamPlayer');

  StreamSubscription<void>? _sub;
  bool _osdVisible = true;
  Timer? _osdHideTimer;

  @override
  void initState() {
    super.initState();
    _screensaverController.setPlaybackActive(true);
    _sub = _service.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Already on this exact list/index when opened from the channels
    // screen's own preview row - openChannels() is cheap to call again
    // regardless (see its own doc) and guarantees this screen always shows
    // what it was asked to, even if it's the sole entry point one day.
    unawaited(_service.openChannels(widget.channels, widget.initialIndex));
    _scheduleOsdAutoHide();
  }

  @override
  void dispose() {
    _osdHideTimer?.cancel();
    _sub?.cancel();
    _screensaverController.setPlaybackActive(false);
    _focusNode.dispose();
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

  Future<void> _zap(int delta) async {
    await _service.zap(delta);
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
    final entry = _service.current;
    if (entry == null) return const SizedBox.shrink();
    final epg = _service.epg;
    final now = DateTime.now();
    final current = epg.isEmpty
        ? null
        : epg.firstWhere(
            (e) => now.isAfter(e.start) && now.isBefore(e.end),
            orElse: () => epg.first,
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
                _service.activeSource?.sourceName ?? entry.sourceName,
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
                    '${_service.currentIndex + 1} / ${_service.channels.length}',
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
    final controller = _service.controller;
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
              if (controller != null)
                Video(controller: controller, controls: NoVideoControls),
              if (_service.loading || _service.buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_service.error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _service.error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => _service.openChannels(
                          _service.channels,
                          _service.currentIndex,
                        ),
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
