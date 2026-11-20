import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/chat.dart';

void main() {
  saveRowTests();
  confirmTests();
  test('parses a poll with tenders, export and status', () {
    final snap = ChatSnapshot.fromJson({
      'epoch': 5,
      'replace': true,
      'total': 2,
      'messages': [
        {'role': 'user', 'text': 'hi', 'tenders': []},
        {
          'role': 'assistant',
          'text': 'ok',
          'export': 'xlsx',
          'ref': '111',
          'tenders': [
            {
              'ref': '111',
              'title': 'Road',
              'authority': 'PWD',
              'location': 'Odisha',
              'value': 50000000,
              'emd': null,
              'due_date': '2026-12-01',
            },
          ],
        },
      ],
      'running': true,
      'label': 'Working...',
      'steps': ['a', 'b'],
      'queued': 2,
      'suggestions': [
        {'label': 'L', 'prompt': 'P'},
      ],
    });
    expect(snap.replace, isTrue);
    expect(snap.messages[0].isUser, isTrue);
    expect(snap.messages[1].export, 'xlsx');
    expect(snap.messages[1].tenders.single.value, 50000000);
    expect(snap.messages[1].tenders.single.emd, isNull);
    expect(snap.running, isTrue);
    expect(snap.queued, 2);
    expect(snap.suggestions.single.prompt, 'P');
    expect(snap.aiReady, isTrue);
  });

  test('splitTables separates table blocks from text', () {
    final parts = splitTables('Intro\n| a | b |\n|---|---|\n| 1 | 2 |\nAfter');
    expect(parts.map((p) => p.$1).toList(), [false, true, false]);
    expect(parts[1].$2.split('\n'), hasLength(3));
  });

  test('bare links in table rows become Documents links', () {
    final out = shortLinksInTables(
      'See https://x.com/a\n| 1 | https://x.com/doc. |\n| 2 | [Docs](https://y.com) |',
    );
    expect(out.split('\n')[0], 'See https://x.com/a');
    expect(out.split('\n')[1], '| 1 | [Documents](https://x.com/doc). |');
    expect(out.split('\n')[2], '| 2 | [Docs](https://y.com) |');
  });
}

void confirmTests() {
  test('a held bid job carries its confirm data', () {
    final m = ChatMessage.fromJson({
      'role': 'assistant',
      'text': 'warning',
      'tenders': [],
      'confirm': {'job': 'price', 'ref': '111', 'index': 3},
    });
    expect(m.confirm!['job'], 'price');
    expect(m.confirm!['index'], 3);
    expect(
      ChatMessage.fromJson({'role': 'assistant', 'text': 'x'}).confirm,
      isNull,
    );
  });
}

void saveRowTests() {
  test('a table row becomes a saveable tender (rupees to crore)', () {
    final row = ChatTender.fromJson({
      'ref': '58103075',
      'title': 'Quarters (G+1)',
      'authority': 'Forest Dept',
      'location': 'Malkangiri, Odisha',
      'value': 21627120.0,
      'emd': 50000,
      'due_date': '2026-11-12',
      'sector': 'Civil',
      'documents': 'https://x/d',
    });
    final t = row.asTender();
    expect(t.id, '58103075');
    expect(t.department, 'Forest Dept');
    expect(t.category, 'Civil');
    expect(t.valueCr, closeTo(2.162712, 1e-9));
    expect(t.emdCr, closeTo(0.005, 1e-9));
    expect(t.deadline, '2026-11-12');
    expect(t.link, 'https://x/d');
    expect(
      ChatTender.fromJson({'ref': '1', 'documents': 'not a link'}).link,
      '',
    );
  });
}
