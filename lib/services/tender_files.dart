import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'file_open.dart';

/// BidAssist's own documents address needs the account token that only the server holds, so a phone cannot open it.
bool isBidAssistLink(String link) => link.contains('api.bidassist.com');

/// "Tender documents": for a BidAssist tender the server fetches the files and the phone opens them as a ZIP; for any
/// other link it is copied, as before.
Future<void> openTenderDocuments(BuildContext context, String link) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!isBidAssistLink(link)) {
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(const SnackBar(content: Text('Link copied.')));
    return;
  }
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Getting the tender documents...'),
      duration: Duration(seconds: 20),
    ),
  );
  try {
    final bytes = await ApiClient().tenderDocuments(link);
    messenger.hideCurrentSnackBar();
    final problem = await saveAndOpen('tender_documents.zip', bytes);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
