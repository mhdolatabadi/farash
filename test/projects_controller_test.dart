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

  List<String> treeNames() => [
    for (final node in controller.tree) '${node.depth}:${node.project.name}',
  ];

  test('builds the tree with depths, siblings by sort order', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: '#2563eb');
    await controller.create(
      name: 'Reports',
      color: '#dc2626',
      parentId: work.id,
    );
    await controller.create(name: 'Home', color: '#16a34a');

    expect(controller.inbox!.displayName, 'صندوق ورودی');
    expect(treeNames(), ['0:Work', '1:Reports', '0:Home']);
    expect(controller.tree.first.hasChildren, isTrue);
    expect(controller.projects.first.isInbox, isTrue);
  });

  test('new projects go after their siblings', () async {
    await controller.load();
    await controller.create(name: 'A', color: '#2563eb');
    await controller.create(name: 'B', color: '#2563eb');

    expect(api.all.map((p) => p.sortOrder), [0, 0, 1]);
  });

  test('reorder saves only the sort orders that changed', () async {
    await controller.load();
    await controller.create(name: 'A', color: '#2563eb');
    await controller.create(name: 'B', color: '#2563eb');
    final c = await controller.create(name: 'C', color: '#2563eb');
    api.updates.clear();

    await controller.reorder(controller.byId(c.id)!, 0);

    expect(treeNames(), ['0:C', '0:A', '0:B']);
    expect(api.updates.map((u) => u.$2.sortOrder), [0, 1, 2]);
  });

  test('archived projects leave the tree and list separately', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: '#2563eb');
    await controller.create(name: 'Sub', color: '#2563eb', parentId: work.id);

    await controller.archive(controller.byId(work.id)!);

    // The parent is archived, so its active child shows at the top level.
    expect(treeNames(), ['0:Sub']);
    expect(controller.archivedProjects.map((p) => p.name), ['Work']);
    expect(controller.byId(work.id), isNull);

    await controller.unarchive(work);
    expect(treeNames(), ['0:Work', '1:Sub']);
  });

  test('a parent loop from the server does not hang the tree', () async {
    api = FakeProjectsApi(
      projects: const [
        Project(id: 'a', name: 'A', color: '#000000', parentId: 'b'),
        Project(id: 'b', name: 'B', color: '#000000', parentId: 'a'),
        Project(id: 'c', name: 'C', color: '#000000'),
      ],
    );
    controller = ProjectsController(api: api, token: () => 'token');
    await controller.load();

    expect(treeNames(), ['0:C']);
  });

  test('moving to the top level sends an empty parent_id', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: '#2563eb');
    final sub = await controller.create(
      name: 'Sub',
      color: '#2563eb',
      parentId: work.id,
    );

    await controller.edit(
      controller.byId(sub.id)!,
      name: 'Sub',
      color: '#2563eb',
      parentId: null,
      isFavorite: false,
    );

    expect(api.updates.last.$2.toJson()['parent_id'], '');
    expect(treeNames(), ['0:Work', '0:Sub']);
  });

  test('editing the Inbox never sends its name or parent', () async {
    await controller.load();
    await controller.edit(
      controller.inbox!,
      name: 'Mine',
      color: '#dc2626',
      parentId: null,
      isFavorite: true,
    );

    final json = api.updates.last.$2.toJson();
    expect(json.containsKey('name'), isFalse);
    expect(json.containsKey('parent_id'), isFalse);
    expect(controller.inbox!.color, '#dc2626');
  });

  test('favourite shows at once and rolls back when the API fails', () async {
    await controller.load();
    final work = await controller.create(name: 'Work', color: '#2563eb');

    await controller.setFavorite(controller.byId(work.id)!, true);
    expect(controller.favorites.map((p) => p.name), ['Work']);

    api.failNext = const ApiException('offline');
    await expectLater(
      controller.setFavorite(controller.byId(work.id)!, false),
      throwsA(isA<ApiException>()),
    );
    expect(controller.favorites.map((p) => p.name), ['Work']);
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

  test('without a token nothing is loaded or sent', () async {
    final signedOut = ProjectsController(api: api, token: () => null);
    await signedOut.load();
    expect(signedOut.projects, isEmpty);
    await expectLater(
      signedOut.create(name: 'x', color: '#2563eb'),
      throwsA(isA<ApiException>()),
    );
  });

  test('Project reads the API JSON', () {
    final project = Project.fromJson({
      'id': 'p1',
      'owner_id': 'u1',
      'parent_id': 'p0',
      'name': 'کار',
      'color': '#4073ff',
      'sort_order': 3,
      'is_favorite': true,
      'is_archived': false,
      'is_inbox': false,
      'kind': 'folder',
      'open_tasks': 2,
    });

    expect(project.parentId, 'p0');
    expect(project.sortOrder, 3);
    expect(project.isFolder, isTrue);
    expect(project.openTasks, 2);
    expect(project.swatch.toARGB32(), 0xFF4073FF);
  });

  test('unknown colors show as grey', () {
    expect(ProjectColor.parse('red').toARGB32(), 0xFF64748B);
    expect(ProjectColor.parse('#12345').toARGB32(), 0xFF64748B);
  });
}
