import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';

class ChatLifecycleManager {
  late Chat chat;
  late final StreamSubscription sub;
  late final StreamSubscription sub2;

  bool isActive = false;
  bool isAlive = false;
  ConversationViewController? controller;

  ChatLifecycleManager(this.chat) {
    if (!kIsWeb) {
      final chatQuery = Database.chats.query(Chat_.guid.equals(chat.guid)).watch();
      sub = chatQuery.listen((Query<Chat> query) async{
        final _chat = await runAsync(() {
          return Database.chats.get(chat.id!);
        });
        if (_chat != null) {
          bool shouldSort = chat.latestMessage.dateCreated != _chat.latestMessage.dateCreated;
          chats.updateChat(_chat, shouldSort: shouldSort);
          chat = _chat.merge(chat);
        }
      });
      // listen for contacts update (this listens for all chats)
      sub2 = eventDispatcher.stream.listen((event) {
        if (event.item1 != 'update-contacts') return;
        if (event.item2.isNotEmpty) {
          reloadContacts(chat, event.item2);
          chats.updateChat(chat, override: true);
        }
      });
    } else {
      sub = WebListeners.chatUpdate.listen((_chat) {
        chats.updateChat(_chat, shouldSort: false);
        chat = _chat.merge(chat);
      });
      sub2 = WebListeners.newMessage.listen((tuple) {
        final message = tuple.item1;
        final _chat = tuple.item2;
        if (_chat?.guid == chat.guid &&
            (chat.latestMessage.dateCreated!.millisecondsSinceEpoch == 0 || message.dateCreated!.isAfter(chat.latestMessage.dateCreated!))) {
          chats.updateChat(_chat!, shouldSort: true);
          chat = _chat.merge(chat);
          chat.latestMessage = message;
        }
      });
    }
  }

  static void reloadContacts(Chat chat, List<List<int>> changed) {
    for (var i = 0; i < chat.participants.length; i++) {
      final h = chat.participants[i];
      if (changed.last.contains(h.id)) {
        chat.participants[i] = Database.handles.get(h.id!)!;
      } else if (changed.first.contains(h.contactRelation.targetId)) {
        h.contactRelation.target = Database.contacts.get(h.contactRelation.targetId);
      }
    }
    chat.title = null;
  }
}
