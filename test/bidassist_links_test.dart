import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/chat.dart';
import 'package:tender_agent_mobile/services/tender_files.dart';

void main() {
  const bidAssist =
      'https://api.bidassist.com/api/tender-listing/v4/documents/download/372a2b59-d421-4e70-b919-ba9f80dbd636?tenderEntity=TENDER_LISTING';

  test('a BidAssist document address in a table row becomes a Docs link', () {
    final out = shortLinksInTables('| 1 | Road work | $bidAssist |');
    expect(out, '| 1 | Road work | [Docs]($bidAssist) |');
  });

  test("the AI's own Markdown link to it becomes a Docs link too", () {
    final out = shortLinksInTables('| 1 | Road | [Tender documents]($bidAssist) |');
    expect(out, '| 1 | Road | [Docs]($bidAssist) |');
  });

  test('a Docs link is the kind the phone downloads through the server', () {
    expect(isBidAssistLink(bidAssist), isTrue);
    expect(isBidAssistLink('https://tenderdetail.biz/Documents?Id=5'), isFalse);
  });

  test('other links still become the short Documents link', () {
    final out = shortLinksInTables(
      '| 1 | Road | https://tenderdetail.biz/Documents?Id=5 |',
    );
    expect(out, '| 1 | Road | [Documents](https://tenderdetail.biz/Documents?Id=5) |');
  });

  test('text outside a table is left alone', () {
    expect(shortLinksInTables('See $bidAssist'), 'See $bidAssist');
  });
}
