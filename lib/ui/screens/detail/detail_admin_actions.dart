import 'package:server_core/server_core.dart';

import '../../widgets/focus/context_action.dart' show canIdentifyItemType;

enum DetailAdminAction { identify, editMetadata, changeArtwork }

/// The admin controls a detail page can offer for one item.
///
/// Delete lives on its own dedicated trash-can button (DetailButton.
/// deleteServer, item_detail_screen.dart) rather than in here - 30.10, Sid
/// ("le rouge il supprime je crois alors que il y a deja un bouton
/// poubelle. Ça fait doublon") - canDelete already drives that button's own
/// visibility (widget.onDelete), so offering the same action a second time
/// inside this dialog was a real duplicate, not a deliberate second path.
/// The metadata actions go through the admin items API, which the Emby
/// client leaves unsupported, so they stay on Jellyfin.
Set<DetailAdminAction> detailAdminActions({
  required ServerType serverType,
  required bool isAdministrator,
  required bool isTV,
  required String? itemType,
  required bool canDelete,
}) {
  return {
    if (isAdministrator && serverType == ServerType.jellyfin) ...{
      if (canIdentifyItemType(itemType)) DetailAdminAction.identify,
      if (!isTV) DetailAdminAction.editMetadata,
      DetailAdminAction.changeArtwork,
    },
  };
}
