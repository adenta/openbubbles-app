import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/types/helpers/carddav_sync.dart';
import 'package:bluebubbles/services/ui/contact_service.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/chat/chat_lifecycle_manager.dart';
import 'package:bluebubbles/services/backend_ui_interop/event_dispatcher.dart';
import 'package:bluebubbles/app/layouts/contact_selector_view/contact_selector_view.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';

class ScratchState implements CardDavStateStore {
  final saved = <String, AddressBook>{};
  bool fail = false;
  void Function()? beforeSave;
  @override
  Future<String?> getCtag(Uri u) async => saved[u.toString()]?.ctag;
  @override
  Future<String?> getSyncToken(Uri u) async => saved[u.toString()]?.syncToken;
  @override
  Future<void> saveCheckpoint(AddressBook b) async {
    beforeSave?.call();
    if (fail) throw StateError('synthetic checkpoint failure');
    saved[b.url.toString()] = b;
  }
}

class StubClient extends CardDavClient {
  Future<List<CardDavSyncResult>> Function() fetch = () async => [];
  StubClient(ScratchState state)
      : super(
            principalUrl: Uri.parse('https://contacts.example.invalid/'),
            state: state,
            authHeadersProvider: () async => {});
  @override
  Future<List<CardDavSyncResult>> syncAllAddressBooks() => fetch();
}

class TestContacts extends ContactsService {
  final CardDavClient client;
  TestContacts(this.client);
  @override
  Future<bool> canAccessContacts() async => true;
  @override
  Future<CardDavClient?> createCardDavClient() async => client;
}

// Exercise the real picker's subscription, search and disposal without unrelated
// app theme/native dependencies in its presentation.
class PickerHarness extends ContactSelectorView {
  PickerHarness() : super(onSelect: (_) {});
  @override
  ContactSelectorViewState createState() => PickerHarnessState();
}

class PickerHarnessState extends ContactSelectorViewState {
  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(controller: searchController),
        for (final c in filteredContacts) Text(c.displayName),
      ]);
}

final book = AddressBook(
    url: Uri.parse('https://contacts.example.invalid/book/'),
    ctag: 'one',
    syncToken: 'token-one');
Uri href(String name) => book.url.resolve('$name.vcf');
Contact contact(String key, {String? email, String? name}) => Contact(
    id: cardDavContactId(href(key)),
    displayName: name ?? key,
    emails: [email ?? '$key@example.invalid']);
ContactChange upsert(String key, {String? email, String? name}) =>
    ContactChange.upsert(
        href: href(key),
        vcard: null,
        contact: contact(key, email: email, name: name));
CardDavSyncResult delta(List<ContactChange> changes) =>
    CardDavSyncResult(book, changes);
const card =
    'BEGIN:VCARD\r\nVERSION:3.0\r\nUID:synthetic-unique-id\r\nFN:Synthetic Person\r\nN:Person;Synthetic;;;\r\nEMAIL:synthetic@example.invalid\r\nEND:VCARD\r\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('failure summaries retain safe categories without private exception details', () {
    expect(contactSyncFailureSummary(ContactSyncError(ContactSyncFailure.cardDownload, 403)),
        'cardDownload; HTTP 403');
    expect(contactSyncFailureSummary(StateError('private-contact-url')), 'StateError');
    expect(contactSyncFailureSummary(DioException(
      requestOptions: RequestOptions(path: 'https://private.invalid/contact'),
      message: 'private-contact-card',
      type: DioExceptionType.badResponse)), 'network badResponse; HTTP 0');
  });
  late Directory scratch;
  late TestContacts service;
  late StubClient client;
  late ScratchState state;
  setUpAll(() {
    ss.settings = Settings();
    scratch = Directory.systemTemp.createTempSync('openbubbles-contact-test-');
    Database.store = Store(getObjectBoxModel(), directory: scratch.path);
    Database.contacts = Database.store.box<Contact>();
    Database.handles = Database.store.box<Handle>();
  });
  tearDownAll(() {
    Database.store.close();
    scratch.deleteSync(recursive: true);
  });
  setUp(() {
    Database.handles.removeAll();
    Database.contacts.removeAll();
    state = ScratchState();
    client = StubClient(state);
    service = TestContacts(client);
    cs = service;
  });

  test(
      'first import publishes complete contacts and committed handle links before checkpoint',
      () async {
    final hid = Database.handles.put(Handle(address: 'first@example.invalid'));
    final notifications = <List<List<int>>>[];
    final sub = eventDispatcher.stream.listen((e) {
      if (e.item1 == 'update-contacts') notifications.add(e.item2);
    });
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    state.beforeSave = () {
      expect(Database.contacts.count(), 1);
      expect(Database.handles.get(hid)!.contactRelation.targetId, isNonZero);
    };
    final changed = await service.refreshContacts();
    await Future<void>.delayed(Duration.zero);
    expect(service.contacts, hasLength(1));
    expect(changed.first, hasLength(1));
    expect(changed.last, [hid]);
    expect(notifications, [changed]);
    expect(state.saved, hasLength(1));
    await sub.cancel();
  });

  test(
      'unchanged server repairs existing handles after reopening; valid matches stay stable',
      () async {
    final id = Database.contacts.put(contact('first'));
    final hid = Database.handles.put(Handle(address: 'first@example.invalid'));
    await service.init();
    client.fetch =
        () async => [CardDavSyncResult(book, [], hasCheckpoint: false)];
    expect((await service.refreshContacts()).last, [hid]);
    expect(Database.handles.get(hid)!.contactRelation.targetId, id);
    expect((await service.refreshContacts()).last, isEmpty);
    expect(service.contacts, hasLength(1));
  });

  test('new message handles match the newly imported in-memory list', () async {
    client.fetch = () async => [delta([upsert('first')])];
    await service.refreshContacts();
    final h = Handle(address: 'first@example.invalid').save();
    expect(h.contactRelation.targetId, service.contacts.single.dbId);
  });

  test('distinct resources insert independently and edits preserve database ID',
      () async {
    client.fetch = () async => [
          delta([upsert('first'), upsert('second')])
        ];
    await service.refreshContacts();
    final firstId = Contact.findOne(id: cardDavContactId(href('first')))!.dbId;
    client.fetch = () async => [
          delta([upsert('first', name: 'Edited'), upsert('third')])
        ];
    await service.refreshContacts();
    expect(Database.contacts.count(), 3);
    expect(Contact.findOne(id: cardDavContactId(href('first')))!.dbId, firstId);
    expect(Contact.findOne(id: cardDavContactId(href('first')))!.displayName,
        'Edited');
  });

  test(
      'deletion is scoped; edited addresses unlink; normal contacts override shared profiles',
      () async {
    final shared = contact('shared', email: 'first@example.invalid')
      ..id = 'shared-profile'
      ..isShared = true;
    shared.dbId = Database.contacts.put(shared);
    final h = Handle(address: 'first@example.invalid')
      ..contactRelation.target = shared;
    final hid = Database.handles.put(h);
    final other = contact('other')
      ..id = 'carddav:https://contacts.example.invalid/other/book.vcf';
    Database.contacts.put(other);
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    await service.refreshContacts();
    expect(Database.handles.get(hid)!.contact!.isShared, false);
    client.fetch = () async => [
          delta([upsert('first', email: 'changed@example.invalid')])
        ];
    await service.refreshContacts();
    expect(Database.handles.get(hid)!.contactRelation.targetId, shared.dbId);
    client.fetch = () async => [
          delta([ContactChange.deleted(href: href('first'))])
        ];
    await service.refreshContacts();
    expect(Database.contacts.count(), 2);
    expect(Contact.findOne(id: other.id), isNotNull);
    expect(Contact.findOne(id: shared.id), isNotNull);
  });

  test(
      'last deletion clears contacts, links and notifies cached conversation objects',
      () async {
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    final hid = Database.handles.put(Handle(address: 'first@example.invalid'));
    final chat = Chat(
        guid: 'synthetic-chat', participants: [Database.handles.get(hid)!]);
    final changed = await service.refreshContacts();
    ChatLifecycleManager.reloadContacts(chat, changed);
    expect(chat.participants.single.displayName, 'first');
    chat.title = 'old cached title';
    client.fetch = () async => [
          delta([ContactChange.deleted(href: href('first'))])
        ];
    final deleted = await service.refreshContacts();
    ChatLifecycleManager.reloadContacts(chat, deleted);
    expect(service.contacts, isEmpty);
    expect(deleted.first, hasLength(1));
    expect(deleted.last, [hid]);
    expect(chat.participants.single.contact, isNull);
    expect(chat.title, isNull);
  });

  test('transaction failure rolls back all contacts and never saves checkpoint',
      () async {
    final invalid = upsert('bad');
    invalid.contact!.id = '';
    client.fetch = () async => [
          delta([upsert('first'), invalid])
        ];
    await expectLater(service.refreshContacts(), throwsStateError);
    expect(Database.contacts.count(), 0);
    expect(state.saved, isEmpty);
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    await service.refreshContacts();
    expect(Database.contacts.count(), 1);
  });

  test('checkpoint failure can replay without duplicate records', () async {
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    state.fail = true;
    await expectLater(service.refreshContacts(), throwsStateError);
    final id = Database.contacts.getAll().single.dbId;
    expect(service.contacts, hasLength(1));
    expect(state.saved, isEmpty);
    state.fail = false;
    await service.refreshContacts();
    expect(Database.contacts.count(), 1);
    expect(Database.contacts.getAll().single.dbId, id);
    expect(state.saved, hasLength(1));
  });

  test(
      'fetch failure preserves records and is sanitized; following retry succeeds',
      () async {
    Database.contacts.put(contact('existing'));
    client.fetch = () async => throw StateError('private-resource-and-contact');
    await expectLater(service.refreshContacts(),
        throwsA(predicate((e) => !e.toString().contains('private-resource'))));
    expect(Database.contacts.count(), 1);
    expect(state.saved, isEmpty);
    client.fetch = () async => [
          delta([upsert('first')])
        ];
    await service.refreshContacts();
    expect(service.contacts, hasLength(2));
  });

  test('overlapping refreshes serialize fetch through checkpoint', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    client.fetch = () async {
      final n = ++calls;
      if (n == 1) {
        entered.complete();
        await release.future;
      }
      return [
        delta([upsert('contact$n')])
      ];
    };
    final first = service.refreshContacts();
    await entered.future;
    final second = service.refreshContacts();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    release.complete();
    await Future.wait([first, second]);
    expect(calls, 2);
    expect(Database.contacts.count(), 2);
  });

  testWidgets(
      'open picker refreshes immediately, preserves query and clears on deletion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PickerHarness())));
    await tester.enterText(find.byType(TextField), 'syn');
    await tester.pump(const Duration(milliseconds: 300));
    client.fetch = () async => [
          delta([
            upsert('first', name: 'Synthetic Person'),
            upsert('second', name: 'Unrelated')
          ])
        ];
    await tester.runAsync(() => service.refreshContacts());
    await tester.pump();
    expect(find.text('Synthetic Person'), findsOneWidget);
    expect(find.text('Unrelated'), findsNothing);
    expect(find.text('syn'), findsOneWidget);
    client.fetch = () async => [
          delta([
            ContactChange.deleted(href: href('first')),
            ContactChange.deleted(href: href('second'))
          ])
        ];
    await tester.runAsync(() => service.refreshContacts());
    await tester.pump();
    expect(find.text('Synthetic Person'), findsNothing);
    expect(find.text('syn'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.completeContactsRefresh([], reloadUI: [[], []]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible avatar refreshes its cached handle after import and deletion', (tester) async {
    final id = Database.handles.put(Handle(address: 'first@example.invalid'));
    final cached = Database.handles.get(id)!;
    await tester.pumpWidget(AdaptiveTheme(
      light: ThemeData.light(), dark: ThemeData.dark(), initial: AdaptiveThemeMode.light,
      builder: (light, dark) => MaterialApp(theme: light, darkTheme: dark,
        home: Scaffold(body: ContactAvatarWidget(handle: cached, editable: false, size: 40))),
    ));
    client.fetch = () async => [delta([upsert('first', name: 'Synthetic Person')])];
    await tester.runAsync(() => service.refreshContacts());
    await tester.pump();
    expect(cached.contact!.displayName, 'Synthetic Person');
    final avatarText = find.byKey(const Key('first@example.invalid-avatar-text'));
    expect(tester.widget<Text>(avatarText).data, anyOf('S', 'SP'));
    client.fetch = () async => [delta([ContactChange.deleted(href: href('first'))])];
    await tester.runAsync(() => service.refreshContacts());
    await tester.pump();
    expect(cached.contact, isNull);
    expect(tester.widget<Text>(avatarText).data, 'F');
    await tester.pumpWidget(const SizedBox());
    service.completeContactsRefresh([], reloadUI: [[], []]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final google in [false, true]) {
    test('collection entries are not downloaded as cards (Google: $google)', () async {
      final target = google
          ? AddressBook(url: Uri.parse('https://www.googleapis.com/carddav/book/'))
          : book;
      final gets = <Uri>[];
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
        final String data;
        if (o.method == 'GET') {
          gets.add(o.uri);
          // The collection rejects GET, as opposed to a real contact resource.
          handler.resolve(Response(requestOptions: o,
              data: o.uri == target.url ? '' : card,
              statusCode: o.uri == target.url ? 400 : 200));
          return;
        }
        data = '<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">'
            '<d:sync-token>next</d:sync-token>'
            '<d:response><d:href>${target.url.path}</d:href><d:propstat><d:prop><cs:getctag>new</cs:getctag></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
            '<d:response><d:href>${target.url.path}person.vcf</d:href><d:propstat><d:prop><d:getetag>one</d:getetag></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';
        handler.resolve(Response(requestOptions: o, data: data, statusCode: 207));
      }));
      final actual = CardDavClient(principalUrl: target.url, state: state,
          dio: dio, authHeadersProvider: () async => {});
      final result = await actual.syncAddressBook(target);
      expect(gets, [target.url.resolve('person.vcf')]);
      expect(result.changes.single.contact!.id, cardDavContactId(gets.single));
      expect(state.saved, isEmpty);
    });
  }

  for (final status in [200, 403, 500, 404]) {
    test(
        'actual CardDAV client handles vCard HTTP $status without premature checkpoints',
        () async {
      final methods = <String>[];
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
        methods.add(o.method);
        final String data;
        if (o.method == 'PROPFIND') {
          data =
              '<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/"><d:response><d:propstat><d:prop><cs:getctag>one</cs:getctag><d:sync-token>token-one</d:sync-token></d:prop></d:propstat></d:response></d:multistatus>';
        } else if (o.method == 'REPORT') {
          data =
              '<d:multistatus xmlns:d="DAV:"><d:sync-token>token-one</d:sync-token><d:response><d:href>/book/person.vcf</d:href><d:propstat><d:prop><d:getetag>etag-one</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>';
        } else if (o.method == 'GET') {
          data = card;
        } else {
          throw StateError('Unexpected synthetic request');
        }
        handler.resolve(Response(
            requestOptions: o,
            data: data,
            statusCode: o.method == 'GET' ? status : 207));
      }));
      final actual = CardDavClient(
          principalUrl: book.url,
          state: state,
          dio: dio,
          authHeadersProvider: () async => {});
      if (status == 403 || status == 500) {
        await expectLater(actual.syncAddressBook(book), throwsStateError);
        expect(state.saved, isEmpty);
      } else {
        final first = await actual.syncAddressBook(book);
        expect(state.saved, isEmpty);
        expect(first.changes, hasLength(1));
        if (status == 200) {
          expect(first.changes.single.contact!.id,
              cardDavContactId(href('person')));
          expect(first.changes.single.contact!.emails,
              ['synthetic@example.invalid']);
        } else {
          expect(first.changes.single.type, ChangeType.deleted);
        }
        await state.saveCheckpoint(first.book);
        final unchanged = await actual.syncAddressBook(book);
        expect(unchanged.changes, isEmpty);
        expect(unchanged.hasCheckpoint, false);
        expect(methods, ['PROPFIND', 'REPORT', 'GET', 'PROPFIND']);
      }
      dio.close();
    });
  }
}
