import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/activity.dart';
import '../models/bid_check.dart';
import '../models/chat.dart';
import '../models/signup.dart';
import '../models/tender.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Tender Mitra backend, proving who we are with the Firebase login token.
class ApiClient {
  /// One request. `auth: false` is for the few public calls (sign-up help, reading sign-up documents).
  /// Returns the response once it is a success; any failure becomes an [ApiException].
  Future<http.Response> _request(
    String method,
    String path, {
    Uint8List? body,
    String contentType = 'application/octet-stream',
    bool auth = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final request = http.Request(method, Uri.parse('$apiBaseUrl$path'));
    if (auth) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        throw ApiException('You are logged out. Please log in again.');
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = contentType;
      request.bodyBytes = body;
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await request.send().timeout(timeout),
      );
    } catch (_) {
      throw ApiException(
        'Could not reach the Tender Mitra server ($apiBaseUrl). Is it running?',
      );
    }
    if (res.statusCode != 200) {
      Object? decoded;
      try {
        decoded = res.body.isEmpty
            ? null
            : jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {}
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiException(
        detail is String ? detail : 'Server error (${res.statusCode}).',
      );
    }
    return res;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Uint8List? body,
    String contentType = 'application/octet-stream',
    bool auth = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final res = await _request(
      method,
      path,
      body: body,
      contentType: contentType,
      auth: auth,
      timeout: timeout,
    );
    final decoded = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path,
    Object payload, {
    bool auth = true,
    Duration timeout = const Duration(seconds: 60),
  }) => _send(
    method,
    path,
    body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    contentType: 'application/json',
    auth: auth,
    timeout: timeout,
  );

  Future<TenderFeed> tenders() async =>
      TenderFeed.fromJson(await _send('GET', '/api/tenders'));

  /// Saves the letterhead on the server (a PDF is converted into a Word letterhead there).
  /// Returns the saved file name.
  Future<String> saveLetterhead(String name, Uint8List data) async {
    final res = await _send(
      'PUT',
      '/api/letterhead?name=${Uri.encodeQueryComponent(name)}',
      body: data,
      timeout: const Duration(minutes: 3),
    );
    return '${res['name']}';
  }

  /// The signatory's name as read from the signature picture, or '' when it can't be read.
  Future<String> readSignatureName(Uint8List image) async {
    final res = await _send(
      'POST',
      '/api/signature-name',
      body: image,
      timeout: const Duration(seconds: 90),
    );
    return '${res['name'] ?? ''}';
  }

  // ---------------------------------------------------------------- sign-up

  /// Company details read out of the sign-up documents (only values that pass the format checks), plus a
  /// note to show when the documents could not be read. Works before the account exists.
  Future<({Map<String, dynamic> values, String note})> autofill(
    List<PickedFile> files,
  ) async {
    final res = await _json(
      'POST',
      '/api/signup/autofill',
      {
        'files': [
          for (final f in files)
            {'name': f.name, 'data': base64Encode(f.bytes)},
        ],
      },
      auth: false,
      timeout: const Duration(minutes: 2),
    );
    return (
      values: Map<String, dynamic>.from(res['values'] as Map? ?? {}),
      note: '${res['note'] ?? ''}',
    );
  }

  /// Saves the company record. The server writes it (and sets the new account to "pending").
  Future<void> saveSignupProfile(Map<String, dynamic> details) => _json(
    'POST',
    '/api/signup/profile',
    details,
    timeout: const Duration(seconds: 90),
  );

  /// Asks the server to analyse the uploaded documents in the background (best effort).
  Future<void> startIndexing() => _send('POST', '/api/signup/index');

  /// "Help me prepare my documents" request from someone who has none yet. No account is created for it.
  Future<void> saveLead(Map<String, dynamic> lead) =>
      _json('POST', '/api/leads', lead, auth: false);

  // ------------------------------------------------- mobile OTP and the free Bid Check

  /// Sends an OTP to the mobile number. Returns the number as the server shows it ("+91 98765 43210") and whether
  /// the number already has an account (then the company name is not needed again).
  Future<({String phone, bool returning})> requestOtp(String phone) async {
    final res = await _json('POST', '/api/otp/request', {
      'phone': phone,
    }, auth: false);
    return (phone: '${res['phone'] ?? phone}', returning: res['returning'] == true);
  }

  /// Checks the OTP. The first time a number signs in its account is made (with this company name). Returns the
  /// Firebase custom token the phone signs in with.
  Future<String> verifyOtp(String phone, String code, String company) async {
    final res = await _json('POST', '/api/otp/verify', {
      'phone': phone,
      'code': code,
      'company_name': company,
    }, auth: false, timeout: const Duration(seconds: 90));
    return '${res['token']}';
  }

  Future<BidCheckStatus> bidCheck() async =>
      BidCheckStatus.fromJson(await _send('GET', '/api/bid-check'));

  /// Adds one file to the check ([kind] is 'tender' or 'bid'). Returns the status with the files added so far.
  Future<void> addBidCheckFile(String kind, String name, Uint8List data) =>
      _send(
        'PUT',
        '/api/bid-check/files?kind=$kind&name=${Uri.encodeQueryComponent(name)}',
        body: data,
        timeout: const Duration(minutes: 3),
      );

  Future<void> clearBidCheckFiles(String kind) =>
      _send('DELETE', '/api/bid-check/files?kind=$kind');

  Future<void> startBidCheck() => _send('POST', '/api/bid-check/start');

  Future<void> clearBidCheck() => _send('POST', '/api/bid-check/clear');

  // ---------------------------------------------------------------- AI Analysis chat

  /// The conversation after message `have` (all of it when the chat was cleared) and what is running now.
  Future<ChatSnapshot> chat({required int have, required int epoch}) async =>
      ChatSnapshot.fromJson(
        await _send('GET', '/api/chat?have=$have&epoch=$epoch'),
      );

  Future<void> chatAsk({String? text, bool best = false}) =>
      _json('POST', '/api/chat/ask', {'text': text, 'best': best});

  /// `force` is "Run anyway": skips the warning about a tender that looks wrong for the company.
  Future<void> chatBid(
    String job,
    int index,
    List<String> refs, {
    bool force = false,
  }) => _json('POST', '/api/chat/bid', {
    'job': job,
    'index': index,
    'refs': refs,
    'force': force,
  });

  Future<void> chatStop() => _send('POST', '/api/chat/stop');

  Future<void> chatClear() => _send('DELETE', '/api/chat');

  /// The Word / Excel file for an answer, built on the server (letterhead, signature, seal, enclosures).
  Future<ChatDownload> chatExport(int index) async {
    final res = await _request(
      'GET',
      '/api/chat/export?index=$index',
      timeout: const Duration(minutes: 3),
    );
    var attached = <String>[], missing = <String>[], name = 'bid.docx';
    try {
      final info = jsonDecode(
        Uri.decodeComponent(res.headers['x-export-info'] ?? '{}'),
      ) as Map;
      attached = [for (final a in info['attached'] as List? ?? []) '$a'];
      missing = [for (final a in info['missing'] as List? ?? []) '$a'];
      name = '${info['name'] ?? name}';
    } catch (_) {}
    return ChatDownload(name, res.bodyBytes, attached, missing);
  }

  // ---------------------------------------------------------------- Agent Activity and Reports

  /// The company's AI agent runs, newest first.
  Future<List<AgentRun>> activity() async {
    final res = await _send('GET', '/api/activity');
    return [
      for (final r in (res['runs'] as List? ?? const []))
        AgentRun.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// A report workbook ("market", "pipeline" or "usage") built on the server, as on the website.
  Future<ReportFile> reportFile(String kind) async {
    final res = await _request(
      'GET',
      '/api/reports/$kind',
      timeout: const Duration(minutes: 2),
    );
    final name = RegExp(r'filename="?([^";]+)"?')
        .firstMatch(res.headers['content-disposition'] ?? '')
        ?.group(1);
    return ReportFile(name ?? '$kind.xlsx', res.bodyBytes);
  }

  // ---------------------------------------------------------------- tender source / BidAssist token

  Future<TenderStatus> tenderStatus() async => TenderStatus.fromJson(
    await _send('GET', '/api/tender-status', timeout: const Duration(seconds: 90)),
  );

  /// Administrators: use BidAssist ('bidassist_api') or TenderDetail ('tenderdetail') for everyone.
  Future<TenderStatus> setTenderSource(String source) async =>
      TenderStatus.fromJson(await _json('POST', '/api/admin/source', {'source': source}));

  /// Administrators: checks the pasted BidAssist token and keeps it when it works. Returns the server's message.
  Future<String> saveBidAssistToken(String token) async {
    final res = await _json(
      'POST',
      '/api/admin/token',
      {'token': token},
      timeout: const Duration(seconds: 90),
    );
    return '${res['message'] ?? 'Token saved.'}';
  }

  Future<TenderStatus> checkBidAssistToken() async => TenderStatus.fromJson(
    await _send('POST', '/api/admin/token/check', timeout: const Duration(seconds: 90)),
  );

  Future<TenderStatus> removeBidAssistToken() async =>
      TenderStatus.fromJson(await _send('DELETE', '/api/admin/token'));

  // ---------------------------------------------------------------- tender documents

  /// The files of a BidAssist tender as one ZIP, fetched by the server (the link itself needs a token).
  Future<Uint8List> tenderDocuments(String link) async =>
      (await _request(
        'GET',
        '/api/tender-documents?link=${Uri.encodeQueryComponent(link)}',
        timeout: const Duration(minutes: 3),
      )).bodyBytes;

  // ---------------------------------------------------------------- live tender search

  /// One page of the live BidAssist search. `page` counts from 1; no `states` means all India.
  Future<LivePage> liveTenders({
    String q = '',
    List<String> states = const [],
    List<String> kinds = const [], // WORKS / SERVICES / GOODS / AUCTION
    String dueFrom = '', // bid deadline range, yyyy-mm-dd
    String dueTo = '',
    String postedFrom = '', // posting date range, yyyy-mm-dd
    String postedTo = '',
    int days = 90,
    String sort = 'Closing soonest',
    int page = 1,
    int size = 10,
  }) async {
    final query = Uri(
      queryParameters: {
        'q': q,
        if (states.isNotEmpty) 'state': states, // repeated: ?state=Odisha&state=Kerala
        if (kinds.isNotEmpty) 'kind': kinds,
        if (dueFrom.isNotEmpty) 'due_from': dueFrom,
        if (dueTo.isNotEmpty) 'due_to': dueTo,
        if (postedFrom.isNotEmpty) 'posted_from': postedFrom,
        if (postedTo.isNotEmpty) 'posted_to': postedTo,
        'days': '$days',
        'sort': sort,
        'page': '$page',
        'size': '$size',
      },
    ).query;
    return LivePage.fromJson(
      await _send(
        'GET',
        '/api/tenders/live?$query',
        timeout: const Duration(seconds: 90),
      ),
    );
  }
}
