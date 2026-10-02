import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel_group.dart';
import '../models/playable_channel.dart';
import 'stream_health_tracker.dart';

/// 01.10, Sid: "à l'ouverture de la page, qu'on ait la même UI que
/// clubtivi et pas juste la liste des chaines" - clubTivi keeps ONE
/// media_kit player alive behind both its mini preview and its fullscreen
/// view, so switching a channel never recreates the video widget and going
/// fullscreen is instant (same stream, same decoder, just a bigger
/// Video()). This service is that same single long-lived player for
/// Moonfin's IPTV screens, extracted out of what used to be
/// XtreamPlayerScreen's own private Player/VideoController - the
/// open/zap/failover logic below is a straight move, not a rewrite.
///
/// Lifecycle: created lazily (GetIt lazy singleton) the first time any IPTV
/// screen calls [openChannels], and torn down explicitly by whichever
/// screen owns "leaving the IPTV section entirely" via [stop] - pushing
/// XtreamPlayerScreen on top of the channels screen must NOT stop this,
/// since that's exactly the fullscreen case this exists to make seamless.
class IptvPlayerService {
  static const _openTimeout = Duration(seconds: 12);
  static const _stallThreshold = Duration(seconds: 8);
  static const _maxFailoverAttempts = 3;

  final _healthTracker = StreamHealthTracker();
  final _stateController = StreamController<void>.broadcast();

  /// Fires after any state field below changes - UI listens and rebuilds.
  Stream<void> get changes => _stateController.stream;

  Player? _player;
  VideoController? _controller;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  Timer? _stallTimer;
  int _openToken = 0;

  List<PlayableChannel> _channels = const [];
  int _currentIndex = 0;

  // 02.10, Sid: "il faudrait que haut/bas me permette de revenir à la
  // précédente que j'ai regardé (pas celle directe à côté)" - a classic TV
  // remote "last channel" toggle, not list-adjacency like left/right zap.
  // Holds the CHANNEL (by streamUrl identity, see PlayableChannel ==
  // elsewhere in this codebase), not a raw index - the index into whatever
  // list was active when this was recorded is meaningless once the user
  // has since switched to a differently-filtered channel list. Only set in
  // openChannels() when the channel actually changes, so a failover
  // re-open (same channel, different source) or a no-op re-call never
  // overwrites it.
  PlayableChannel? _previousChannel;

  int _alternativeIndex = 0;
  int _failoverAttempts = 0;
  final Set<String> _triedSourcesThisChannel = {};
  List<ChannelGroup> _groups = const [];

  bool _loading = true;
  bool _buffering = false;
  String? _error;
  List<EpgEntryData> _epg = const [];

  VideoController? get controller => _controller;
  bool get hasChannel => _channels.isNotEmpty;
  List<PlayableChannel> get channels => _channels;
  int get currentIndex => _currentIndex;
  bool get loading => _loading;
  bool get buffering => _buffering;
  String? get error => _error;
  List<EpgEntryData> get epg => _epg;

  PlayableChannel? get current =>
      _currentIndex < _channels.length ? _channels[_currentIndex] : null;

  ChannelGroup _groupFor(PlayableChannel channel) => _groups.firstWhere(
    (g) => g.alternatives.contains(channel),
    orElse: () => ChannelGroup(key: '', alternatives: [channel]),
  );

  /// The source actually feeding the player right now - [current] unless a
  /// Smart Channels failover has switched to one of its alternatives.
  PlayableChannel? get activeSource {
    final c = current;
    if (c == null) return null;
    final group = _groupFor(c);
    if (_alternativeIndex >= group.alternatives.length) return c;
    return group.alternatives[_alternativeIndex];
  }

  void _notify() => _stateController.add(null);

  void _ensurePlayer() {
    if (_player != null) return;
    _player = Player(configuration: const PlayerConfiguration(libass: false));
    _controller = VideoController(_player!);
    _bufferingSub = _player!.stream.buffering.listen((b) {
      _buffering = b;
      _notify();
      if (b) {
        _stallTimer ??= Timer(_stallThreshold, _tryFailover);
      } else {
        _stallTimer?.cancel();
        _stallTimer = null;
        _failoverAttempts = 0;
      }
    });
    _errorSub = _player!.stream.error.listen((message) {
      final c = current;
      if (c == null) return;
      final group = _groupFor(c);
      if (group.alternatives.length > 1 &&
          _failoverAttempts < _maxFailoverAttempts) {
        unawaited(_tryFailover());
        return;
      }
      _loading = false;
      _error = message;
      _notify();
    });
  }

  /// Opens [channels][index] in the shared player. Safe to call repeatedly
  /// (e.g. once per sidebar/EPG selection) - a call for the same channel
  /// list and index the player is already on is still worth re-running
  /// since the list identity (and therefore the zap/failover group) may
  /// have changed even if the index didn't.
  Future<void> openChannels(List<PlayableChannel> channels, int index) async {
    _ensurePlayer();
    final token = ++_openToken;
    _stallTimer?.cancel();
    _stallTimer = null;
    _alternativeIndex = 0;
    _failoverAttempts = 0;
    _triedSourcesThisChannel.clear();
    final leavingChannel = current;
    final enteringChannel =
        index >= 0 && index < channels.length ? channels[index] : null;
    if (leavingChannel != null &&
        enteringChannel != null &&
        leavingChannel.streamUrl != enteringChannel.streamUrl) {
      _previousChannel = leavingChannel;
    }
    _channels = channels;
    _groups = ChannelGroup.groupChannels(channels);
    _currentIndex = index;
    _loading = true;
    _error = null;
    _epg = const [];
    _notify();

    final entry = _channels[index];
    try {
      await _player!.open(Media(entry.streamUrl)).timeout(_openTimeout);
      if (token != _openToken) return;
      _loading = false;
      _notify();
      unawaited(_healthTracker.recordSuccess(entry.streamUrl));
    } on TimeoutException {
      if (token != _openToken) return;
      // 02.10, bug trouvé en audit: _tryFailover() s'incrémente son propre
      // _openToken en interne - recharger l'EPG avec CE token (le plus
      // récent), pas l'ancien `token` de cette méthode, sinon le `return`
      // ci-dessous sautait purement et simplement _loadEpg et la chaîne de
      // secours affichait un programme vide jusqu'au prochain changement.
      if (await _tryFailover()) {
        unawaited(_loadEpg(_openToken));
        return;
      }
      if (token != _openToken) return;
      _loading = false;
      _error = 'La chaîne ne répond pas (délai dépassé)';
      _notify();
    } catch (_) {
      if (token != _openToken) return;
      if (await _tryFailover()) {
        unawaited(_loadEpg(_openToken));
        return;
      }
      if (token != _openToken) return;
      _loading = false;
      _error = 'Impossible de lire cette chaîne';
      _notify();
    }

    unawaited(_loadEpg(token));
  }

  Future<void> zap(int delta) async {
    final count = _channels.length;
    if (count <= 1) return;
    final newIndex = (_currentIndex + delta) % count;
    await openChannels(_channels, newIndex < 0 ? newIndex + count : newIndex);
  }

  /// Toggles back to whichever channel was active before the last real
  /// switch - a TV remote's classic "last channel" button, not list
  /// adjacency (that's zap). Looked up by streamUrl in the CURRENT channel
  /// list since _previousChannel may have been recorded against a
  /// differently-filtered list; does nothing if that channel isn't in the
  /// list currently open (e.g. a filter was applied since).
  Future<void> jumpToPreviousChannel() async {
    final target = _previousChannel;
    if (target == null) return;
    final index = _channels.indexWhere((c) => c.streamUrl == target.streamUrl);
    if (index < 0 || index == _currentIndex) return;
    await openChannels(_channels, index);
  }

  /// Tries the next source configured for this same logical channel (see
  /// ChannelGroup), up to [_maxFailoverAttempts] - called after
  /// [_stallThreshold] of continuous buffering, on a hard player error, or
  /// when opening a source times out/throws. Leaves [_currentIndex] and the
  /// EPG alone: from the viewer's side this is still the same channel,
  /// just a different source under it.
  Future<bool> _tryFailover() async {
    _stallTimer = null;
    final c = current;
    if (c == null) return false;

    final group = _groupFor(c);
    if (group.alternatives.length <= 1) return false;
    if (_failoverAttempts >= _maxFailoverAttempts) return false;

    final active = activeSource;
    if (active != null) {
      unawaited(_healthTracker.recordFailure(active.streamUrl));
      _triedSourcesThisChannel.add(active.streamUrl);
    }

    final ordered = _healthTracker.orderByReliability(group.alternatives);
    final next = ordered
        .where((c) => !_triedSourcesThisChannel.contains(c.streamUrl))
        .firstOrNull;
    if (next == null) return false;

    _failoverAttempts++;
    _alternativeIndex = group.alternatives.indexOf(next);
    _triedSourcesThisChannel.add(next.streamUrl);

    final token = ++_openToken;
    try {
      await _player!.open(Media(next.streamUrl)).timeout(_openTimeout);
      unawaited(_healthTracker.recordSuccess(next.streamUrl));
    } catch (_) {
      // 02.10, bug trouvé en audit: opening this alternative itself
      // failed/timed out outright (not just slow to buffer) - retry
      // immediately with whatever's left rather than counting on the
      // buffering stream below to re-arm the stall timer, which isn't
      // guaranteed to flip true on a hard failure (unsupported codec,
      // connection refused...). Without this, the loading spinner could
      // get stuck forever with failover attempts still unspent.
      if (token == _openToken) return _tryFailover();
      return true;
    }
    if (token != _openToken) return true;

    // media_kit's buffering stream only fires on a real transition, and it
    // can easily stay continuously true across the open() above (still
    // buffering on the new source) - nothing would toggle it false-then-
    // true again to re-arm the listener's own timer, so this re-arms
    // itself directly whenever there are attempts left to spend.
    if (_buffering && _failoverAttempts < _maxFailoverAttempts) {
      _stallTimer = Timer(_stallThreshold, _tryFailover);
    }
    _notify();
    return true;
  }

  Future<void> _loadEpg(int token) async {
    final fetchEpg = current?.fetchEpg;
    if (fetchEpg == null) return;
    final listings = await fetchEpg();
    if (token != _openToken) return;
    _epg = listings;
    _notify();
  }

  /// Stops and tears down the shared player. Call only when actually
  /// leaving the IPTV section (not when pushing a fullscreen route on top
  /// of a screen that still owns this service).
  void stop() {
    _cancelSubscriptions();
    _player?.stop();
    _player?.dispose();
    _player = null;
    _controller = null;
    _channels = const [];
    _epg = const [];
  }

  void _cancelSubscriptions() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _bufferingSub?.cancel();
    _errorSub?.cancel();
  }
}
