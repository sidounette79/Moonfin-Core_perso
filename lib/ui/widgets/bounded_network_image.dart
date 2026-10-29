import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../util/image_fetch_priority.dart';
import '../theme/vibrance.dart';
import 'image_source.dart';

export '../../util/image_fetch_priority.dart' show ImageFetchPriority;

/// A [CachedNetworkImage] whose decoded pixel width is bounded to the
/// rendered widget width times the device pixel ratio, optionally clamped
/// and/or scaled. This keeps the in-memory image cache from holding decodes
/// far larger than what is actually painted (a common source of jank and
/// large RAM usage on web).
///
/// The sizing rules live in [ArtworkDecode]. This widget adds the
/// [onLoadFinished] contract the game screens depend on.
class BoundedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Duration fadeInDuration;
  final Widget Function(BuildContext context, String url, Object error)?
  errorBuilder;
  final VoidCallback? onLoadFinished;
  final BaseCacheManager? cacheManager;

  /// Multiplier applied to the resolved width before clamping. Useful for
  /// blurred images where a low-resolution decode is acceptable.
  final double scale;

  /// Lower bound for the decoded width in physical pixels.
  final int minWidth;

  /// Upper bound for the decoded width in physical pixels.
  final int maxWidth;

  /// The image's own aspect ratio, for cover fits into a box narrower than
  /// the source. See [ArtworkDecode.widthFor].
  final double? sourceAspectRatio;

  /// An explicit decode width, used verbatim instead of the layout. For a
  /// widget whose precache must land on exactly the same key.
  final int? memCacheWidth;

  /// Which lane the fetch goes in. See [ImageFetchPriority].
  final ImageFetchPriority priority;

  const BoundedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fadeInDuration = Duration.zero,
    this.errorBuilder,
    this.onLoadFinished,
    this.cacheManager,
    this.scale = 1.0,
    this.minWidth = 64,
    this.maxWidth = 1024,
    this.sourceAspectRatio,
    this.memCacheWidth,
    this.priority = ImageFetchPriority.normal,
  });

  /// The decoded pixel width upstream uses for every bounded image: the painted
  /// width in physical pixels, stepped up and clamped. Public so the game
  /// artwork widgets, which decode from bytes rather than a URL and so can't
  /// use this widget itself, size their decodes by the same rule instead of
  /// a constant.
  static int cacheWidthFor(
    double layoutWidth,
    double devicePixelRatio, {
    double scale = 1.0,
    int minWidth = 64,
    int maxWidth = 1024,
  }) => ArtworkDecode.widthFor(
    layoutWidth,
    devicePixelRatio,
    scale: scale,
    minWidth: minWidth,
    maxWidth: maxWidth,
  );

  static Future<void> precache(
    BuildContext context,
    String imageUrl, {
    required double layoutWidth,
    double? layoutHeight,
    double? sourceAspectRatio,
    double scale = 1.0,
    int minWidth = 64,
    int maxWidth = 1024,
    ImageFetchPriority priority = ImageFetchPriority.low,
  }) => ArtworkDecode.precache(
    context,
    imageUrl,
    layoutWidth: layoutWidth,
    layoutHeight: layoutHeight,
    sourceAspectRatio: sourceAspectRatio,
    scale: scale,
    minWidth: minWidth,
    maxWidth: maxWidth,
    priority: priority,
  );

  @override
  State<BoundedNetworkImage> createState() => _BoundedNetworkImageState();
}

class _BoundedNetworkImageState extends State<BoundedNetworkImage> {
  // 29.10, Sid report ("écran noir, je vais sur une autre vignette ça
  // restaure la miniature noire de celui qui était noir") - a transient
  // failure right after returning from playback (server regenerating a
  // thumbnail, a brief network hiccup) gets painted as a permanent error:
  // Flutter's ImageCache caches a failed resolution under the same
  // provider key as a success, so without a real client-side change
  // nothing ever retries. Navigating to another tile happened to change
  // this card's decode width (focus-scale), which produced a different
  // key and so a fresh, unfailed attempt - same fix, done automatically
  // instead of needing the workaround. One retry only, so a genuinely
  // missing image still settles on the placeholder.
  int _attempt = 0;
  bool _retried = false;

  void _handleError(String url) {
    if (_retried || !mounted) return;
    _retried = true;
    unawaited(ArtworkDecode.evict(url));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _attempt++);
    });
  }

  @override
  void didUpdateWidget(BoundedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retried = false;
      _attempt = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Vibrance.wrap(
      ArtworkBound(
        memCacheWidth: widget.memCacheWidth,
        scale: widget.scale,
        minWidth: widget.minWidth,
        maxWidth: widget.maxWidth,
        sourceAspectRatio: widget.sourceAspectRatio,
        builder: _buildImage,
      ),
    );
  }

  Widget _buildImage(
    BuildContext context,
    int? decodeWidth,
    int? decodeHeight,
  ) {
    final imageUrl = widget.imageUrl;
    final local = isLocalImagePath(imageUrl);
    final headers = local ? null : artworkFetchHeaders(imageUrl, widget.priority);
    final bounded = ArtworkDecode.provider(
      imageUrl,
      width: decodeWidth,
      height: decodeHeight,
      headers: headers,
      cacheManager: widget.cacheManager,
    );
    if (local) {
      return Image(
        key: ValueKey('local#$_attempt#$imageUrl'),
        image: bounded,
        fit: widget.fit,
        alignment: widget.alignment,
        frameBuilder: widget.onLoadFinished == null
            ? null
            : (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null || wasSynchronouslyLoaded) {
                  _notifyLoadFinished();
                }
                return child;
              },
        errorBuilder: (context, error, stackTrace) {
          _notifyLoadFinished();
          _handleError(imageUrl);
          return widget.errorBuilder?.call(context, imageUrl, error) ??
              const SizedBox.shrink();
        },
      );
    }
    return CachedNetworkImage(
      key: ValueKey('cached#$_attempt#$imageUrl'),
      imageUrl: imageUrl,
      httpHeaders: headers,
      cacheManager: widget.cacheManager,
      fit: widget.fit,
      alignment: widget.alignment,
      fadeInDuration: widget.fadeInDuration,
      memCacheWidth: decodeWidth,
      memCacheHeight: decodeHeight,
      imageBuilder: widget.onLoadFinished == null
          ? null
          : (context, _) {
              _notifyLoadFinished();
              // CachedNetworkImage hands this builder the unwrapped provider,
              // so memCacheWidth above never reaches it and the bound has to
              // be applied again or the decode runs at the full source size.
              return Image(image: bounded, fit: widget.fit, alignment: widget.alignment);
            },
      errorWidget: (context, url, error) {
        _notifyLoadFinished();
        _handleError(imageUrl);
        return widget.errorBuilder?.call(context, url, error) ??
            const SizedBox.shrink();
      },
    );
  }

  void _notifyLoadFinished() {
    final callback = widget.onLoadFinished;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }
}
