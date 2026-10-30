import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/detail_admin_actions.dart';
import 'package:server_core/server_core.dart';

Set<DetailAdminAction> actions({
  ServerType serverType = ServerType.jellyfin,
  bool isAdministrator = true,
  bool isTV = false,
  String? itemType = 'Movie',
  bool canDelete = true,
}) => detailAdminActions(
  serverType: serverType,
  isAdministrator: isAdministrator,
  isTV: isTV,
  itemType: itemType,
  canDelete: canDelete,
);

void main() {
  // 30.10, Sid ("le rouge il supprime je crois alors que il y a deja un
  // bouton poubelle. Ça fait doublon") - delete moved out of this dialog
  // entirely onto its own dedicated trash-can button
  // (DetailButton.deleteServer), so it's no longer part of the set
  // detailAdminActions() returns - these groups used to cover that path,
  // kept here only as the "nothing admin-items-api-related on Emby" case.
  group('on Emby', () {
    test('nothing - Emby does not support the admin items api', () {
      expect(actions(serverType: ServerType.emby), isEmpty);
    });
  });

  group('on Jellyfin', () {
    test('an admin gets the whole set on a phone', () {
      expect(actions(), DetailAdminAction.values.toSet());
    });

    test('metadata editing stays off the TV layout', () {
      final result = actions(isTV: true);
      expect(result, isNot(contains(DetailAdminAction.editMetadata)));
      expect(result, contains(DetailAdminAction.changeArtwork));
    });

    test('identify is only offered for types it knows how to look up', () {
      expect(
        actions(itemType: 'Audio'),
        isNot(contains(DetailAdminAction.identify)),
      );
    });

    test('a non admin sees nothing', () {
      expect(actions(isAdministrator: false), isEmpty);
    });
  });
}
