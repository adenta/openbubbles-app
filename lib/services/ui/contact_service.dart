import 'dart:convert';
import 'package:synchronized/synchronized.dart';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/types/helpers/carddav_sync.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/utils/string_utils.dart';
import 'package:dio/dio.dart';
import 'package:fast_contacts/fast_contacts.dart' hide Contact, StructuredName;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;

ContactsService cs = Get.isRegistered<ContactsService>() ? Get.find<ContactsService>() : Get.put(ContactsService());

class ContactsService extends GetxService {
  final tag = "ContactsService";
  /// The master list of contact objects
  List<Contact> contacts = [];

  bool _hasContactAccess = false;
  final Lock _refreshLock = Lock();

  Future<bool> get hasContactAccess async {
    if (_hasContactAccess) return true;

    _hasContactAccess = await canAccessContacts();
    return _hasContactAccess;
  }

  Future<void> init() async {
    // Load the contact access state
    await hasContactAccess;

    if (!kIsWeb) {
      contacts = Contact.getContacts();
    } else {
      await refreshContacts();
    }
  }

  Future<bool> canAccessContacts() async {
    if (kIsWeb || kIsDesktop) {
      int versionCode = (await ss.getServerDetails()).item4;
      return versionCode >= 42 || usingRustPush;
    } else {
      return (await Permission.contacts.status).isGranted;
    }
  }

  Future<List<List<int>>> refreshContacts() => _refreshLock.synchronized(() async {
    if ((kIsDesktop || kIsWeb) && usingRustPush) {
      try {
        return await _refreshCardDavContacts();
      } catch (error) {
        // Network exceptions can contain credentials, resource URLs and vCards.
        Logger.warn('Contact sync failed (${error.runtimeType}); retry is safe');
        throw StateError('Contact sync failed; please retry');
      }
    }
    return _refreshLegacyContacts();
  });

  Future<List<List<int>>> _refreshLegacyContacts() async {
    if (!(await hasContactAccess)) return [];

    // Check if the user is on v1.5.2 or newer
    int serverVersion = (await ss.getServerDetails()).item4;
    // 100(major) + 21(minor) + 1(bug)
    bool isMin1_5_2 = serverVersion >= 207; // Server: v1.5.2

    final startTime = DateTime.now().millisecondsSinceEpoch;
    List<Contact> _contacts = [];
    final changedIds = <List<int>>[<int>[], <int>[]];

    _contacts = await fetchAllContacts();

    // compare loaded contacts to db contacts
    if (!kIsWeb) {
      final dbContacts = Database.contacts.getAll();
      // save any updated contacts
      for (Contact c in dbContacts) {
        final refreshedContact = _contacts.firstWhereOrNull((element) => element.id == c.id);
        if (refreshedContact != null) {
          refreshedContact.dbId = c.dbId;
          if (c != refreshedContact) {
            changedIds.first.add(c.dbId!);
            refreshedContact.save();
          }
        }
      }
      // save any new contacts
      final newContacts = _contacts.where((e) => !dbContacts.map((e2) => e2.id).contains(e.id)).toList();
      if (newContacts.isNotEmpty) {
        final ids = Database.contacts.putMany(newContacts);
        for (int i = 0; i < newContacts.length; i++) {
          newContacts[i].dbId = ids[i];
        }
      }
    }
    // load stored handles
    final List<Handle> handles = [];
    if (kIsWeb) {
      handles.addAll(chats.webCachedHandles);
    } else {
      handles.addAll(Database.handles.getAll());
    }
    // get formatted addresses
    for (Handle h in handles) {
      if (!h.address.contains("@") && h.formattedAddress == null) {
        h.formattedAddress = await formatPhoneNumber(h.address);
      }
    }
    // match handles to contacts and save match
    final handlesToSearch = List<Handle>.from(handles);
    for (Contact c in _contacts) {
      final handles = matchContactToHandles(c, handlesToSearch);
      final addressesAndServices = handles.map((e) => e.uniqueAddressAndService).toList();
      if (handles.isNotEmpty) {
        handlesToSearch.removeWhere((e) => addressesAndServices.contains(e.uniqueAddressAndService));

        // we have changes if the handle doesn't have an associated contact,
        // even if there were no contact changes in the first place
        final matches = handles.where((e) => addressesAndServices.contains(e.uniqueAddressAndService));
        for (Handle h in matches) {
          if (kIsWeb) {
            h.webContact = c;
            continue;
          }

          if (h.contactRelation.target == null) {
            changedIds.last.add(h.id!);
          } else if (c.isShared) {
            // we have an existing contact, and we're shared.
            continue;
          }

          h.contactRelation.target = c;
        }
      }
    }
    if (!kIsWeb) {
      Handle.bulkSave(handles, matchOnOriginalROWID: isMin1_5_2);
    } else {
      // dummy to make the full contacts UI refresh happen on web
      changedIds.last.add(handles.length);
      contacts = _contacts;
      for (Chat c in chats.chats) {
        c.webSyncParticipants();
      }
      chats.chats.refresh();
    }

    final endTime = DateTime.now().millisecondsSinceEpoch;
    Logger.debug("Contact refresh took ${endTime - startTime} ms");

    // only return contacts if things changed (or on web)
    return changedIds;
  }

  Future<List<Contact>> fetchAllContacts() async {
    final _contacts = <Contact>[];

    int startTime = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb || kIsDesktop) {
      _contacts.addAll(await fetchNetworkContacts());
      int endTime = DateTime.now().millisecondsSinceEpoch;
      Logger.debug("Contacts fetched in ${endTime - startTime} ms");
    } else {
      _contacts.addAll((await FastContacts.getAllContacts(
        fields: List<ContactField>.from(ContactField.values)
          ..removeWhere((e) => [ContactField.company, ContactField.department, ContactField.jobDescription, ContactField.emailLabels, ContactField.phoneLabels].contains(e))
      )).map((e) => Contact(
        displayName: e.displayName,
        emails: e.emails.map((e) => e.address).toList(),
        phones: e.phones.map((e) => e.number).toList(),
        structuredName: e.structuredName == null ? null : StructuredName(
          namePrefix: e.structuredName!.namePrefix,
          givenName: e.structuredName!.givenName,
          middleName: e.structuredName!.middleName,
          familyName: e.structuredName!.familyName,
          nameSuffix: e.structuredName!.nameSuffix,
        ),
        id: e.id,
      )));

      int endTime = DateTime.now().millisecondsSinceEpoch;
      Logger.debug("Contacts fetched in ${endTime - startTime} ms");

      // get avatars
      startTime = DateTime.now().millisecondsSinceEpoch;
      for (Contact c in _contacts) {
        c.avatar = await getContactAvatar(c.id);
      }

      endTime = DateTime.now().millisecondsSinceEpoch;
      Logger.debug("Avatars fetched in ${endTime - startTime} ms");
    }

    return _contacts;
  }

  Future<Uint8List?> getContactAvatar(String id) async {
    Uint8List? avatar;

    try {
      avatar = await FastContacts.getContactImage(id, size: ContactImageSize.fullSize);
    } catch (e) {
      Logger.warn("Failed to get full size avatar for ID, $id!", error: e);
    }

    if (avatar == null) {
      try {
        avatar = await FastContacts.getContactImage(id);
      } catch (e) {
        Logger.warn("Failed to get small size avatar for ID, $id!", error: e);
      }
    }

    return avatar;
  }

  void completeContactsRefresh(List<Contact> refreshedContacts, {List<List<int>>? reloadUI}) {
    // Legacy/mobile callers use an empty list to mean "no changes".
    if (refreshedContacts.isEmpty && !((kIsDesktop || kIsWeb) && usingRustPush)) return;
    contacts = List<Contact>.from(refreshedContacts);
    if (reloadUI != null) {
      eventDispatcher.emit('update-contacts', reloadUI);
    }
  }

  List<Handle> matchContactToHandles(Contact c, List<Handle> handles) {
    final numericPhones = c.phones.map((e) => e.numericOnly()).toList();
    List<Handle> handleMatches = [];
    // multiply phones by 3 because a phone can be matched to iMessage / SMS / Android SMS
    int maxResults = c.phones.length * 3 + c.emails.length;
    for (Handle h in handles) {
      // Match emails
      if (h.address.contains("@") && c.emails.contains(h.address)) {
        handleMatches.add(h);
        continue;
      }

      final numericAddress = h.address.numericOnly();

      // Match phone numbers (exact)
      if (c.phones.contains(numericAddress)) {
        handleMatches.add(h);
        continue;
      }

      // try to match last 15 - 7 digits
      for (String p in numericPhones) {
        // remove leading zeros which indicate "same country"
        final leadingZerosRemoved = int.tryParse(p)?.toString() ?? p;
        final matchLengths = [15, 14, 13, 12, 11, 10, 9, 8, 7];
        if (matchLengths.contains(leadingZerosRemoved.length) && numericAddress.endsWith(leadingZerosRemoved)) {
          handleMatches.add(h);
          continue;
        }
      }

      if (handleMatches.length >= maxResults) break;
    }

    return handleMatches;
  }

  Contact? matchHandleToContact(Handle h) {
    if (!_hasContactAccess) return null;

    Contact? contact;
    final numericAddress = h.address.numericOnly();
    for (Contact c in contacts) {
      final numericPhones = c.phones.map((e) => e.numericOnly()).toList();
      if (h.address.contains("@") && c.emails.contains(h.address)) {
        contact = c;
        break;
      } else {
        // if address is direct match
        if (c.phones.contains(numericAddress)) {
          contact = c;
          break;
        }
        // try to match last 11 - 7 digits
        for (String p in numericPhones) {
          final matchLengths = [15, 14, 13, 12, 11, 10, 9, 8, 7];
          if (matchLengths.contains(p.length) && numericAddress.endsWith(p)) {
            contact = c;
            break;
          }
        }
        if (contact != null) break;
      }
    }
    return contact;
  }

  Contact? getContact(String address) {
    final tempHandle = Handle(
      address: address
    );
    return matchHandleToContact(tempHandle);
  }

  /// Authentication stays with the existing provider; tests supply a synthetic client.
  Future<CardDavClient?> createCardDavClient() async {
    final CardDavClient client;

    if (ss.settings.contactSyncProvider.value == "Google") {
      var account = await pushService.googleSignIn.signInOffline();
      if (account == null) {
        Logger.warn("No google auth!");
        return null;
      }

      final response = await http.dio.post(
        'https://oauth2.googleapis.com/token',
        data: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': account.refreshToken,
          'grant_type': 'refresh_token',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Failed to refresh Google access token',
          type: DioExceptionType.badResponse,
        );
      }

      client = CardDavClient(
        principalUrl: Uri.parse('https://www.googleapis.com/.well-known/carddav'),
        authHeadersProvider: () async {
          return {
            "Authorization": "Bearer ${response.data['access_token'] as String}"
          };
        },
        state: SettingsCardDavStateStore(),
      );
    } else if (ss.settings.contactSyncProvider.value == "CardDav") {
      if (ss.settings.cardDavServer.value == "") return null;
      client = CardDavClient(
        principalUrl: Uri.parse(ss.settings.cardDavServer.value),
        username: ss.settings.cardDavUser.value,
        password: ss.settings.cardDavPass.value,
        state: SettingsCardDavStateStore(),
      );
    } else {
      if (pushService.state?.icloudServices == null) return null;
      client = CardDavClient(
        principalUrl: Uri.parse('https://contacts.icloud.com/'),
        authHeadersProvider: () async {
          return await api.getContactsHeaders(path: pushService.statePath, state: pushService.state!.anisette, tokenProvider: pushService.state!.icloudServices!.tokenProvider, config: pushService.state!.osConfig);
        },
        state: SettingsCardDavStateStore(),
      );
    }

    return client;
  }

  Future<List<List<int>>> _refreshCardDavContacts() async {
    if (!(await hasContactAccess)) return [];
    final watch = Stopwatch()..start();
    final client = await createCardDavClient();
    final results = client == null ? <CardDavSyncResult>[] : await client.syncAllAddressBooks();
    final changed = applyCardDavChanges(results);
    // Publish committed records even if saving a checkpoint subsequently fails.
    completeContactsRefresh(kIsWeb ? contacts : Contact.getContacts(), reloadUI: changed);
    if (kIsWeb) {
      for (final chat in chats.chats) {
        chat.webSyncParticipants();
      }
      chats.chats.refresh();
    }
    if (client != null) {
      for (final result in results.where((r) => r.hasCheckpoint)) {
        await client.state.saveCheckpoint(result.book);
      }
    }
    Logger.info('Contact sync ${client == null ? "unavailable; using cache" : "completed"}: '
        '${contacts.length} contacts, ${changed.first.length} changed, '
        '${changed.last.length} relinked, ${watch.elapsedMilliseconds} ms');
    return changed;
  }

  /// Contacts and handle links commit together. No network or preferences writes here.
  List<List<int>> applyCardDavChanges(List<CardDavSyncResult> results) {
    List<List<int>> apply() {
      final changedContacts = <int>{};
      final changedHandles = <int>{};
      // ObjectBox clears incoming relations when a target is deleted. Capture
      // their old values first so the UI still receives those link changes.
      final originalHandles = kIsWeb ? chats.webCachedHandles : Database.handles.getAll();
      final originalLinks = {
        for (final h in originalHandles)
          h.id: kIsWeb ? h.webContact?.id : h.contactRelation.targetId,
      };
      final stored = kIsWeb ? List<Contact>.from(contacts) : Contact.getContacts();
      final byId = {for (final c in stored) c.id: c};
      for (final result in results) {
        for (final change in result.changes) {
          final id = cardDavContactId(change.href);
          final existing = byId[id];
          if (change.type == ChangeType.deleted) {
            if (existing == null || existing.isShared) continue;
            if (existing.dbId != null) changedContacts.add(existing.dbId!);
            if (!kIsWeb) Database.contacts.remove(existing.dbId!);
            byId.remove(id);
          } else {
            final incoming = change.contact!;
            if (incoming.id != id || incoming.isShared || (existing?.isShared ?? false)) {
              throw StateError('Invalid imported contact identity');
            }
            incoming.dbId = existing?.dbId;
            incoming.isDismissed = existing?.isDismissed ?? false;
            incoming.posterPath = existing?.posterPath;
            // Put by stable ID directly; Contact.save's legacy lookup is not needed.
            if (!kIsWeb) incoming.dbId = Database.contacts.put(incoming);
            if (incoming.dbId != null) changedContacts.add(incoming.dbId!);
            byId[id] = incoming;
          }
        }
      }
      final allContacts = kIsWeb ? byId.values.toList() : Contact.getContacts();
      final handles = kIsWeb ? chats.webCachedHandles : Database.handles.getAll();
      for (final handle in handles) {
        final oldId = originalLinks[handle.id];
        final candidates = allContacts.where((c) => matchContactToHandles(c, [handle]).isNotEmpty).toList();
        final normal = candidates.where((c) => !c.isShared).toList();
        final preferred = normal.isNotEmpty ? normal : candidates;
        final match = preferred.firstWhereOrNull((c) => (kIsWeb ? c.id : c.dbId) == oldId) ?? preferred.firstOrNull;
        if (kIsWeb) {
          handle.webContact = match;
          if (oldId != match?.id && handle.id != null) changedHandles.add(handle.id!);
        } else {
          handle.contactRelation.target = match;
          if (oldId != handle.contactRelation.targetId) changedHandles.add(handle.id!);
        }
      }
      if (!kIsWeb) Database.handles.putMany(handles);
      if (kIsWeb) contacts = allContacts;
      return [changedContacts.toList(), changedHandles.toList()];
    }
    return kIsWeb ? apply() : Database.runInTransaction(TxMode.write, apply);
  }

  Future<List<Contact>> fetchNetworkContacts({Function(String)? logger}) async {
    final networkContacts = <Contact>[];

    if (usingRustPush) {
      await refreshContacts();
      return List<Contact>.from(contacts);
    }

    // refresh UI on web without waiting for avatars
    if (kIsWeb) {
      logger?.call("Fetching contacts (no avatars)...");
      try {
        final response = await http.contacts();

        if (response.statusCode == 200 && !isNullOrEmpty(response.data['data'])) {
          logger?.call("Found contacts!");

          for (Map<String, dynamic> map in response.data['data']) {
            final displayName = getDisplayName(map['displayName'], map['firstName'], map['lastName']);
            final emails = (map['emails'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            final phones = (map['phoneNumbers'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            logger?.call("Parsing contact: $displayName");
            networkContacts.add(Contact(
              id: (map['id'] ?? (phones.isNotEmpty ? phones : emails)).toString(),
              displayName: displayName,
              emails: emails,
              phones: phones,
            ));
          }
        } else {
          logger?.call("No contacts found!");
        }
        logger?.call("Finished contacts sync (no avatars)");
      } catch (e, s) {
        logger?.call("Got exception: $e");
        logger?.call(s.toString());
      }
      final handlesToSearch = List<Handle>.from(chats.webCachedHandles);
      for (Contact c in contacts) {
        final handles = matchContactToHandles(c, handlesToSearch);
        final addressesAndServices = handles.map((e) => e.uniqueAddressAndService).toList();
        if (handles.isNotEmpty) {
          handlesToSearch.removeWhere((e) => addressesAndServices.contains(e.uniqueAddressAndService));
          for (Handle h in handles) {
            if (addressesAndServices.contains(h.uniqueAddressAndService)) {
              h.webContact = c;
            }
          }
        }
      }
      eventDispatcher.emit('update-contacts', null);
    }

    logger?.call("Fetching contacts (with avatars)...");
    try {
      if (kIsWeb) {
        final response = await http.contacts(withAvatars: true);

        if (!isNullOrEmpty(response.data['data'])) {
          logger?.call("Found contacts!");
          for (Map<String, dynamic> map in response.data['data'].where((e) => !isNullOrEmpty(e['avatar']))) {
            final displayName = getDisplayName(map['displayName'], map['firstName'], map['lastName']);
            logger?.call("Adding avatar for contact: $displayName");
            final emails = (map['emails'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            final phones = (map['phoneNumbers'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            for (Contact contact in networkContacts) {
              bool match = contact.id == (map['id'] ?? (phones.isNotEmpty ? phones : emails)).toString();

              // Ensure contact first name matches to avoid issues with shared numbers (landlines)
              if (!match && map['firstName'] != null && !contact.displayName.startsWith(map['firstName'])) continue;

              List<String> addresses = [...contact.phones, ...contact.emails];
              List<String> _addresses = [...phones, ...emails];
              for (String a in addresses) {
                if (match) {
                  break;
                }
                String? formatA = a.contains("@") ? a.toLowerCase() : await formatPhoneNumber(cleansePhoneNumber(a));
                if (formatA.isEmpty) continue;
                for (String _a in _addresses) {
                  String? _formatA = _a.contains("@") ? _a.toLowerCase() : await formatPhoneNumber(cleansePhoneNumber(_a));
                  if (formatA == _formatA) {
                    match = true;
                    break;
                  }
                }
              }

              if (match && contact.avatar == null) {
                contact.avatar = base64Decode(map['avatar'].toString());
              }
            }
          }
        } else {
          logger?.call("No contacts found!");
        }
        logger?.call("Finished contacts sync (with avatars)");
      } else {
        final response = await http.contacts(withAvatars: true);

        if (response.statusCode == 200 && !isNullOrEmpty(response.data['data'])) {
          logger?.call("Found contacts!");
          for (Map<String, dynamic> map in response.data['data']) {
            final displayName = getDisplayName(map['displayName'], map['firstName'], map['lastName']);
            final emails = (map['emails'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            final phones = (map['phoneNumbers'] as List<dynamic>? ?? []).map((e) => e['address'].toString()).toList();
            logger?.call("Parsing contact: $displayName");

            // Log when a contact has no saved addresses
            if (emails.isEmpty && phones.isEmpty) {
              logger?.call("Contact has no saved addresses: $displayName");
            }
            
            networkContacts.add(Contact(
              id: (map['id'] ?? (phones.isNotEmpty ? phones : emails)).toString(),
              displayName: displayName,
              emails: emails,
              phones: phones,
              avatar: !isNullOrEmpty(map['avatar']) ? base64Decode(map['avatar'].toString()) : null,
            ));
          }
        } else {
          logger?.call("No contacts found!");
        }
        logger?.call("Finished contacts sync (with avatars)");
      }
    } catch (e, s) {
      logger?.call("Got exception: $e");
      logger?.call(s.toString());
    }
    return networkContacts;
  }
}
