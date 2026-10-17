import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_inbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

SupportChatMessage _msg(String id, SupportMessageSender sender, int ts) => SupportChatMessage(
      id: id,
      text: 'text $id',
      sender: sender,
      timestamp: ts,
      status: SupportMessageStatus.sent,
    );

void main() {
  test('support inbox: history is not announced, new operator replies are, the chat suppresses them', () async {
    final inbox = SupportInbox.instance;
    var replies = <SupportChatMessage>[];
    var sounds = 0;
    List<SupportChatMessage> next = [];
    int? lastSince;
    SharedPreferences.setMockInitialValues({});
    inbox.clientId = () async => 'client_a';

    inbox.fetch = ({int? since}) async {
      lastSince = since;
      final out = next;
      next = [];
      return out;
    };
    inbox.onReply = replies.add;
    inbox.onSound = () => sounds++;
    inbox.chatOpen = false;

    // First poll: the history that is already there. Nothing is announced.
    next = [_msg('u1', SupportMessageSender.user, 1000), _msg('s1', SupportMessageSender.support, 1500)];
    await inbox.poll();
    expect(replies, isEmpty);
    expect(sounds, 0);

    // A new operator reply arrives: one sound, one banner with that reply, polling from the newest ts.
    next = [_msg('s2', SupportMessageSender.support, 2000)];
    await inbox.poll();
    expect(lastSince, 1500);
    expect(replies.map((m) => m.id), ['s2']);
    expect(sounds, 1);

    // The user's own message is not a reply: nothing shows.
    next = [_msg('u2', SupportMessageSender.user, 2500)];
    await inbox.poll();
    expect(replies.length, 1);
    expect(sounds, 1);

    // The chat is open: it shows the reply itself, the inbox stays quiet but keeps its place.
    inbox.chatOpen = true;
    next = [_msg('s3', SupportMessageSender.support, 3000)];
    await inbox.poll();
    expect(replies.length, 1);
    expect(sounds, 1);
    expect(lastSince, 2500);
    inbox.chatOpen = false;
  });

  test('support inbox: an old reply never comes back after a failed poll or a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final inbox = SupportInbox.instance;
    final replies = <SupportChatMessage>[];
    final history = [
      _msg('u1', SupportMessageSender.user, 1000),
      _msg('s1', SupportMessageSender.support, 1500),
    ];
    List<SupportChatMessage>? next;
    inbox.clientId = () async => 'client_b';
    inbox.fetch = ({int? since}) async =>
        next?.where((m) => since == null || m.timestamp > since).toList();
    inbox.onReply = replies.add;
    inbox.onSound = null;
    inbox.chatOpen = false;

    // Offline at launch: the poll fails. It must not count as "seen, nothing there".
    next = null;
    await inbox.poll();
    // Back online: the server returns the whole history. Still the first look — silent.
    next = history;
    await inbox.poll();
    expect(replies, isEmpty);

    // App restarted (the mark is on disk): the same history is not announced again.
    await inbox.poll();
    expect(replies, isEmpty);

    // The chat screen showed a reply: the banner does not repeat it later.
    next = [...history, _msg('s2', SupportMessageSender.support, 2000)];
    await inbox.markSeen(2000);
    await inbox.poll();
    expect(replies, isEmpty);

    // A really new reply shows exactly once.
    next = [...next, _msg('s3', SupportMessageSender.support, 3000)];
    await inbox.poll();
    await inbox.poll();
    expect(replies.map((m) => m.id), ['s3']);
  });

  test('support inbox: the closed notice is a plaque in the chat, not a banner', () async {
    SharedPreferences.setMockInitialValues({'support_inbox_seen_client_c': 1000});
    final inbox = SupportInbox.instance;
    final replies = <SupportChatMessage>[];
    inbox.clientId = () async => 'client_c';
    inbox.fetch = ({int? since}) async => [
          const SupportChatMessage(id: 'tg_1', text: 'x', sender: SupportMessageSender.support, timestamp: 2000, kind: 'closed'),
        ];
    inbox.onReply = replies.add;
    inbox.onSound = null;
    inbox.chatOpen = false;
    await inbox.poll();
    expect(replies, isEmpty);
  });
}
