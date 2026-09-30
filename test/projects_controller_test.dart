import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';

import 'support/fake_projects_api.dart';

void main() {
  late FakeProjectsApi api;
  late ProjectsController controller;

  setUp(() {
    api = FakeProjectsApi();
    controller = ProjectsController(api: api, token: () => 'token');
  });

  test('loads the Inbox and builds the tree with depths', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: 'blue');
    await controller.create(name: 'Reports', color: 'red', parentId: work.id);
    await controller.create(name: 'Home', color: 'green');

    expect(controller.inbox!.displayName, 'صندوق ورودی');
    expect(
      [
        for (final node in controller.tree)
          '${node.depth}:${node.project.name}',
      ],
      ['0:Work', '1:Reports', '0:Home'],
    );
    expect(controller.tree.first.hasChildren, isTrue);
  });

  test('reorder moves a project among its siblings', () async {
    await controller.load();
    await controller.create(name: 'A', color: 'blue');
    await controller.create(name: 'B', color: 'blue');
    final c = await controller.create(name: 'C', color: 'blue');

    await controller.reorder(controller.byId(c.id)!, 0);

    expect(
      [for (final node in controller.tree) node.project.name],
      ['C', 'A', 'B'],
    );
  });

  test('favourite shows at once and rolls back when the API fails', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: 'blue');

    await controller.setFavorite(controller.byId(work.id)!, true);
    expect(controller.favorites.map((p) => p.name), ['Work']);

    api.failNext = const ApiException('offline');
    await expectLater(
      controller.setFavorite(controller.byId(work.id)!, false),
      throwsA(isA<ApiException>()),
    );
    expect(controller.favorites.map((p) => p.name), ['Work']);
  });

  test('archive hides a project and unarchive brings it back', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: 'blue');

    await controller.archive(controller.byId(work.id)!);
    expect(controller.byId(work.id), isNull);
    expect((await controller.archived()).map((p) => p.name), ['Work']);

    await controller.unarchive(work);
    expect(controller.byId(work.id), isNotNull);
  });

  test('a failed load keeps the error for a retry', () async {
    api.failNext = const ApiException('offline');
    await controller.load();

    expect(controller.error, isA<ApiException>());
    expect(controller.projects, isEmpty);

    await controller.load();
    expect(controller.error, isNull);
    expect(controller.inbox, isNotNull);
  });

  test('without a token nothing is loaded', () async {
    final signedOut = ProjectsController(api: api, token: () => null);
    await signedOut.load();
    expect(signedOut.projects, isEmpty);
    await expectLater(
      signedOut.create(name: 'x', color: 'blue'),
      throwsA(isA<ApiException>()),
    );
  });

  test('clear forgets the account', () async {
    await controller.load();
    controller.clear();
    expect(controller.projects, isEmpty);
  });

  test('ProjectColor falls back to charcoal for unknown keys', () {
    expect(ProjectColor.of('nope').key, 'charcoal');
    expect(ProjectColor.all, hasLength(20));
  });
}
