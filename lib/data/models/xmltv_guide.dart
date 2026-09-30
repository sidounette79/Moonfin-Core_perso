/// A single `<channel>` entry from an XMLTV guide: its own id (the value
/// programmes reference via their `channel` attribute) plus whatever
/// display names/icon the guide gives it - a guide commonly lists more than
/// one `<display-name>` for the same channel (e.g. a call-sign and a full
/// name), all of which are candidates for [EpgChannelMatcher]'s fuzzy match.
class XmltvChannel {
  final String id;
  final List<String> displayNames;
  final String? iconUrl;

  const XmltvChannel({
    required this.id,
    required this.displayNames,
    this.iconUrl,
  });
}

/// A single `<programme>` entry, already resolved to real [DateTime]s (see
/// XmltvRepository._parseXmltvTime) and tied to the XMLTV channel id it
/// aired on.
class XmltvProgramme {
  final String channelId;
  final String title;
  final DateTime start;
  final DateTime stop;

  const XmltvProgramme({
    required this.channelId,
    required this.title,
    required this.start,
    required this.stop,
  });
}

/// A fully parsed guide: every channel and programme the feed listed, plain
/// data with no matching applied yet.
class XmltvGuide {
  final List<XmltvChannel> channels;
  final List<XmltvProgramme> programmes;

  const XmltvGuide({required this.channels, required this.programmes});
}
