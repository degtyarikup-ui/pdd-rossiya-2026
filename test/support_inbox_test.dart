import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_inbox.dart';

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
}
