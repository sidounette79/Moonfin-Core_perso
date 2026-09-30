import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../models/xmltv_guide.dart';

/// 30.09, Sid: "un vrai lecteur iptv" - fetches and parses a provider's
/// XMLTV guide feed (the standard format most IPTV panels publish EPG in,
/// separate from the M3U playlist itself). See EpgChannelMatcher for how a
/// parsed guide's channels get matched against M3U playlist entries.
class XmltvRepository {
  final _dio = Dio();

  Future<XmltvGuide?> fetchGuide(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;
      return _parse(body);
    } catch (_) {
      return null;
    }
  }

  XmltvGuide? _parse(String body) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return null;
    }

    final channels = <XmltvChannel>[];
    for (final el in doc.findAllElements('channel')) {
      final id = el.getAttribute('id');
      if (id == null || id.isEmpty) continue;
      final names = el
          .findElements('display-name')
          .map((e) => e.innerText.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isEmpty) continue;
      final icon = el.findElements('icon').firstOrNull?.getAttribute('src');
      channels.add(XmltvChannel(id: id, displayNames: names, iconUrl: icon));
    }

    final programmes = <XmltvProgramme>[];
    for (final el in doc.findAllElements('programme')) {
      final channelId = el.getAttribute('channel');
      final startRaw = el.getAttribute('start');
      final stopRaw = el.getAttribute('stop');
      final title = el.findElements('title').firstOrNull?.innerText.trim();
      if (channelId == null ||
          startRaw == null ||
          stopRaw == null ||
          title == null ||
          title.isEmpty) {
        continue;
      }
      final start = _parseXmltvTime(startRaw);
      final stop = _parseXmltvTime(stopRaw);
      if (start == null || stop == null) continue;
      programmes.add(
        XmltvProgramme(
          channelId: channelId,
          title: title,
          start: start,
          stop: stop,
        ),
      );
    }

    return XmltvGuide(channels: channels, programmes: programmes);
  }

  /// XMLTV timestamps look like `20260930120000 +0000` - 14 digits then an
  /// optional space and a `+HHMM`/`-HHMM` UTC offset. `DateTime.parse`
  /// doesn't accept this shape at all, so it's built by hand.
  static DateTime? _parseXmltvTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length < 14) return null;
    final year = int.tryParse(trimmed.substring(0, 4));
    final month = int.tryParse(trimmed.substring(4, 6));
    final day = int.tryParse(trimmed.substring(6, 8));
    final hour = int.tryParse(trimmed.substring(8, 10));
    final minute = int.tryParse(trimmed.substring(10, 12));
    final second = int.tryParse(trimmed.substring(12, 14));
    if ([year, month, day, hour, minute, second].contains(null)) return null;

    var utc = DateTime.utc(year!, month!, day!, hour!, minute!, second!);

    final offsetMatch = RegExp(
      r'([+-])(\d{2})(\d{2})\s*$',
    ).firstMatch(trimmed);
    if (offsetMatch != null) {
      final sign = offsetMatch.group(1) == '-' ? -1 : 1;
      final offsetHours = int.parse(offsetMatch.group(2)!);
      final offsetMinutes = int.parse(offsetMatch.group(3)!);
      final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
      utc = sign > 0 ? utc.subtract(offset) : utc.add(offset);
    }

    return utc.toLocal();
  }

  void dispose() {
    _dio.close(force: true);
  }
}
