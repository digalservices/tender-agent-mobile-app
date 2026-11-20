import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/company_details.dart';
import '../models/signup.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/document_service.dart';
import '../theme.dart';

/// The six sign-up steps, as on the website: login, tender readiness (checklist + uploads), company details,
/// contact & address, other documents, review & create.
///
/// With `existing` set, the account already exists but has no company record (sign-up was not finished), so
/// the wizard starts at step 2 and finishes without creating an account.
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.auth,
    required this.onFinished,
    required this.onBackToLogin,
    this.existing,
  });
  final AuthService auth;
  final VoidCallback onFinished;
  final VoidCallback onBackToLogin;
  final User? existing;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _Extra {
  _Extra(this.file) : name = TextEditingController();
  final PickedFile file;
  final TextEditingController name;
}

class _SignupScreenState extends State<SignupScreen> {
  static const _titles = [
    ('Create your login', "Use your work email. You'll sign in with it."),
    ('Tender readiness', 'Tick the documents you have and upload each one.'),
    (
      'Company details',
      'Legal and registration information about your business.',
    ),
    ('Contact & address', 'Who should we reach, and where are you based?'),
    (
      'Other documents',
      'Your ticked documents are already attached. Add anything else (company profile, extra work orders...) - this step is optional.',
    ),
    ('Review & confirm', 'Check your details, then create your account.'),
  ];

  final _api = ApiClient();
  final _draft = SignupDraft();
  final _c = <String, TextEditingController>{};
  final _extras = <_Extra>[];
  final _help = {
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'city': TextEditingController(),
    'note': TextEditingController(),
  };
  final _helpNeeded = <String>{};

  late int _step = widget.existing != null ? 1 : 0;
  late User? _user = widget.existing;
  List<String> _errors = [];
  String? _busyText; // shown while something runs
  String? _autofillNote;
  String? _autofillSignature;
  String? _leadName;
  bool _hidePassword = true;
  bool _created = false; // the Firebase account exists - a retry only saves the profile and documents

  bool get _busy => _busyText != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _draft.email = widget.existing!.email ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      ..._c.values,
      ..._help.values,
      ..._extras.map((e) => e.name),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(String key) => _c.putIfAbsent(key, () {
    final initial = switch (key) {
      'email' => _draft.email,
      'password' => _draft.password,
      'confirm' => _draft.confirm,
      'turnover' => rupeesFromCrore(_draft.data['annual_turnover_cr']),
      _ => '${_draft.data[key] ?? ''}',
    };
    return TextEditingController(text: initial);
  });

  String _text(String key) => _ctl(key).text.trim();

  /// Keeps what was typed in this step's boxes, so going Back and forward never loses it.
  void _collect() {
    switch (_step) {
      case 0:
        _draft.email = _text('email').toLowerCase();
        _draft.password = _ctl('password').text;
        _draft.confirm = _ctl('confirm').text;
      case 2:
        for (final k in _companyKeys) {
          _draft.data[k] = _text(k);
        }
        _draft.data['annual_turnover_cr'] = croreFromRupees(_text('turnover'));
      case 3:
        for (final k in _contactKeys) {
          _draft.data[k] = _text(k);
        }
      case 4:
        _draft.extraFiles
          ..clear()
          ..addAll([
            for (final e in _extras)
              PickedFile(namedFile(e.file.name, e.name.text), e.file.bytes),
          ]);
    }
  }

  static const _companyKeys = [
    'company_name',
    'registration_number',
    'year_established',
    'gstin',
    'pan',
    'udyam_number',
    'website',
  ];
  static const _contactKeys = [
    'contact_person',
    'phone',
    'products_services',
    'address',
    'city',
    'pincode',
  ];

  void _goto(int step) => setState(() {
    _step = step;
    _errors = [];
  });

  void _back() {
    _collect();
    if (_step == 0) {
      widget.onBackToLogin();
    } else if (_step == 1 && widget.existing != null) {
      return; // nowhere earlier to go
    } else {
      _goto(_step - 1);
    }
  }

  void _next(List<String> errors) {
    _collect();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
    } else {
      _goto(_step + 1);
    }
  }

  // ------------------------------------------------------------------ file picking

  /// Adds one or more files to a ticked document. A second pick adds to the first ("PAN card.pdf", "PAN card (2).pdf"...).
  Future<void> _pickDoc(SignupDoc doc) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: signupFileTypes,
      );
    } catch (e) {
      setState(() => _errors = ['Could not open the file picker: $e']);
      return;
    }
    final kept = _draft.docFiles[doc.key] ?? [];
    final problems = <String>[];
    final added = <PickedFile>[];
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      final p = validateFile(f.name, bytes.length);
      if (p.isEmpty) {
        added.add(
          PickedFile(
            docFileName(doc.label, f.name, kept.length + added.length + 1),
            bytes,
          ),
        );
      } else {
        problems.addAll(p);
      }
    }
    setState(() {
      _errors = problems;
      if (added.isNotEmpty) _draft.docFiles[doc.key] = [...kept, ...added];
    });
  }

  Future<void> _pickExtras() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: signupFileTypes,
      );
    } catch (e) {
      setState(() => _errors = ['Could not open the file picker: $e']);
      return;
    }
    final problems = <String>[];
    final added = <_Extra>[];
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      final p = validateFile(f.name, bytes.length);
      if (p.isEmpty) {
        added.add(_Extra(PickedFile(f.name, bytes)));
      } else {
        problems.addAll(p);
      }
    }
    setState(() {
      _extras.addAll(added);
      _errors = problems;
    });
  }

  // ------------------------------------------------------------------ steps

  void _step1Continue() => _next(
    validateAccount(
      _text('email').toLowerCase(),
      _ctl('password').text,
      _ctl('confirm').text,
    ),
  );

  Future<void> _step2Continue() async {
    final errors = <String>[
      if (_draft.registered == null)
        'Answer whether you have a registered company.',
      for (final d in signupDocumentsFor(_draft.registered))
        if (_draft.ticked.contains(d.key) &&
            (_draft.docFiles[d.key] ?? const []).isEmpty)
          'Upload your ${d.label}, or untick it.',
    ];
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    await _autofill();
    if (mounted) _goto(2);
  }

  /// Reads the uploaded documents once (again only if they change) and fills still-empty fields of steps 3-4.
  Future<void> _autofill() async {
    final files = _draft.docFiles.values.expand((f) => f).toList();
    final signature = files.map((f) => '${f.name}:${f.bytes.length}').join('|');
    if (files.isEmpty || signature == _autofillSignature) return;
    _autofillSignature = signature;
    setState(
      () => _busyText = 'Reading your documents to fill in your details...',
    );
    try {
      final found = await _api.autofill(files);
      _draft.applyAutofill(found.values);
      for (final e in found.values.entries) {
        final c = _c[e.key];
        if (e.key == 'annual_turnover_cr') continue; // shown in rupees below
        if (c != null && c.text.trim().isEmpty) c.text = '${e.value}';
      }
      final t = _c['turnover'];
      final fromDocs = rupeesFromCrore(found.values['annual_turnover_cr']);
      if (t != null && t.text.trim().isEmpty && fromDocs.isNotEmpty) {
        t.text = fromDocs;
      }
      _autofillNote = found.note.isEmpty ? null : found.note;
    } on ApiException catch (e) {
      _autofillNote =
          e.message; // not fatal - the person just fills the form in themselves
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  Future<void> _sendLead() async {
    final name = _help['name']!.text.trim();
    final phone = phoneDigits(_help['phone']!.text);
    final errors = [
      if (name.isEmpty) 'Enter your name.',
      if (!isValidPhone(phone)) 'Enter a valid 10-digit mobile number.',
    ];
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final offered = signupDocumentsFor(_draft.registered)
        .map((d) => d.label)
        .toList();
    setState(() => _busyText = 'Sending your request...');
    try {
      await _api.saveLead({
        'name': name,
        'phone': phone,
        'city': _help['city']!.text.trim(),
        'email': _text('email'),
        'registered_company': _draft.registered,
        'documents_needed': _helpNeeded.isEmpty
            ? offered
            : _helpNeeded.toList(),
        'note': _help['note']!.text.trim(),
      });
      if (mounted) setState(() => _leadName = name);
    } on ApiException catch (e) {
      if (mounted)
        setState(() => _errors = ['Could not send your request: ${e.message}']);
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  void _step3Continue() {
    _collect();
    _next(validateCompanyStep(_draft.data));
  }

  void _step4Continue() {
    _collect();
    _next(validateContactStep(_draft.data));
  }

  /// Creates the account (unless it exists), saves the company record through the server, uploads the documents.
  Future<void> _create() async {
    _collect();
    setState(() {
      _errors = [];
      _busyText = 'Creating your account...';
    });
    try {
      if (_user == null) {
        _user = await widget.auth.createAccount(_draft.email, _draft.password);
        _created = true;
      }
      setState(() => _busyText = 'Saving your company details...');
      await _api.saveSignupProfile(_draft.details());

      final files = _draft.allFiles;
      final failed = <String>[];
      final uploader = DocumentService();
      for (var i = 0; i < files.length; i++) {
        setState(
          () => _busyText =
              'Uploading document ${i + 1} of ${files.length}: ${files[i].name}',
        );
        try {
          await uploader.upload(_user!.uid, files[i].name, files[i].bytes);
        } catch (e) {
          failed.add('${files[i].name}: $e');
        }
      }
      if (files.isNotEmpty && failed.length < files.length) {
        try {
          await _api.startIndexing();
        } catch (
          _
        ) {} // the documents are analysed the next time the agent starts
      }
      if (!mounted) return;
      if (failed.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Account created'),
            content: Text(
              'Your details are saved, but some documents could not be uploaded. You can add them later in Settings.\n\n${failed.join('\n')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      authRefresh.value++;
      widget.onFinished();
    } on AuthException catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _errors = [
            'Your account is created, but your company details could not be saved: ${e.message}',
            'Tap "Try again" to save them.',
          ],
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errors = ['Something went wrong: $e']);
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  // ------------------------------------------------------------------ widgets

  Widget _field(
    String key,
    String label, {
    String? hint,
    TextInputType? type,
    TextCapitalization caps = TextCapitalization.none,
    int lines = 1,
    int? maxLength,
    bool obscure = false,
    Widget? suffix,
    bool digitsOnly = false,
    String? Function(String text)? helper,
  }) {
    final c = _ctl(key);
    final filled =
        _draft.autofilled[key] != null &&
        _draft.autofilled[key] == c.text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        textCapitalization: caps,
        minLines: lines,
        maxLines: obscure ? 1 : (lines == 1 ? 1 : 6),
        maxLength: maxLength,
        obscureText: obscure,
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        onChanged: (_) {
          if (filled || helper != null) setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          helperText: helper?.call(c.text),
          helperStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          suffixIcon:
              suffix ??
              (filled
                  ? Icon(Icons.check_circle, color: Colors.green.shade700)
                  : null),
        ),
      ),
    );
  }

  Widget _dropdown(String key, String label, List<String> items) {
    final value = items.contains(_draft.data[key])
        ? _draft.data[key] as String
        : null;
    final filled =
        _draft.autofilled[key] != null && _draft.autofilled[key] == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: filled
              ? Icon(Icons.check_circle, color: Colors.green.shade700)
              : null,
        ),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i,
              child: Text(i, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _draft.data[key] = v),
      ),
    );
  }

  Widget _nav({
    required String next,
    required VoidCallback? onNext,
    bool showBack = true,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        if (showBack) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _back,
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _busy ? null : onNext,
            child: Text(next),
          ),
        ),
      ],
    ),
  );

  Widget _errorBox() => _errors.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _errors.map((e) => '• $e').join('\n'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );

  Widget _filledNote(List<String> keys) {
    final shown = keys.any(
      (k) => _draft.autofilled[k] != null && _draft.autofilled[k] == _text(k),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_autofillNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$_autofillNote Please fill in the form yourself.',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ),
        if (shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '✔ Filled from your documents - please check these.',
              style: TextStyle(color: Colors.green.shade700),
            ),
          ),
      ],
    );
  }

  Widget _accountStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Text('Already have an account?'),
          TextButton(
            onPressed: widget.onBackToLogin,
            child: const Text('Log in'),
          ),
        ],
      ),
      _field(
        'email',
        'Work email *',
        hint: 'you@company.com',
        type: TextInputType.emailAddress,
      ),
      _field(
        'password',
        'Password * (min. $minPassword characters)',
        obscure: _hidePassword,
        suffix: IconButton(
          icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _hidePassword = !_hidePassword),
        ),
      ),
      _field('confirm', 'Confirm password *', obscure: _hidePassword),
      _errorBox(),
      _nav(next: 'Continue', onNext: _step1Continue, showBack: false),
    ],
  );

  Widget _readinessStep() {
    final docs = signupDocumentsFor(_draft.registered);
    final none = _draft.registered != null && _draft.ticked.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Do you have a registered company? *'),
        RadioGroup<bool>(
          groupValue: _draft.registered,
          onChanged: (v) => setState(() {
            _draft.registered = v;
            _draft.syncTicks();
          }),
          child: const Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  value: true,
                  title: Text('Yes'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  value: false,
                  title: Text('No'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        if (_draft.registered == false)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'You can still bid on many tenders as a proprietor or individual. Some tenders need a registered company - the agent will point those out.',
            ),
          ),
        if (_draft.registered != null) ...[
          const Text(
            'Documents tenders usually require - tick the ones you have:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final d in docs) ...[
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _draft.ticked.contains(d.key),
              title: Text(d.label),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _draft.ticked.add(d.key);
                } else {
                  _draft.ticked.remove(d.key);
                  _draft.docFiles.remove(d.key);
                }
              }),
            ),
            if (_draft.ticked.contains(d.key))
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (_draft.docFiles[d.key] ?? const []).isNotEmpty
                            ? '📎 ${_draft.docFiles[d.key]!.map((f) => f.name).join(', ')}'
                            : 'Upload required *',
                        key: ValueKey('doc-files-${d.key}'),
                        style: TextStyle(
                          color: (_draft.docFiles[d.key] ?? const []).isNotEmpty
                              ? null
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                    if ((_draft.docFiles[d.key] ?? const []).isNotEmpty)
                      IconButton(
                        tooltip: 'Remove these files',
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _draft.docFiles.remove(d.key),
                              ),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    OutlinedButton.icon(
                      key: ValueKey('doc-pick-${d.key}'),
                      onPressed: _busy ? null : () => _pickDoc(d),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(
                        (_draft.docFiles[d.key] ?? const []).isNotEmpty
                            ? 'Add more'
                            : 'Upload',
                      ),
                    ),
                  ],
                ),
              ),
          ],
          Text(
            '${_draft.ticked.length} of ${docs.length} documents ticked.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        _errorBox(),
        if (none)
          _helpForm()
        else
          _nav(
            next: 'Continue',
            onNext: _step2Continue,
            showBack: widget.existing == null,
          ),
      ],
    );
  }

  /// Shown instead of Continue when nothing is ticked: ask for help preparing documents (no account is made).
  Widget _helpForm() {
    final offered = signupDocumentsFor(_draft.registered);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "You'll need some documents before you can bid.",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tenders ask for at least PAN, GST, bank details and past work proof. Our team can help you prepare them - leave your details and we\'ll contact you.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _help['name'],
              decoration: const InputDecoration(labelText: 'Your name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _help['phone'],
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Phone number * (10-digit mobile)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _help['city'],
              decoration: const InputDecoration(labelText: 'City'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Documents you need help with (none selected = all of them)',
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final d in offered)
                  FilterChip(
                    label: Text(d.label, style: const TextStyle(fontSize: 12)),
                    selected: _helpNeeded.contains(d.label),
                    onSelected: (on) => setState(
                      () => on
                          ? _helpNeeded.add(d.label)
                          : _helpNeeded.remove(d.label),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _help['note'],
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Anything else? (optional)',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _sendLead,
              child: const Text('Request help with documents'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _companyStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _filledNote(_companyKeys),
      _field(
        'company_name',
        'Company name *',
        hint: 'Acme Infra Pvt Ltd',
        caps: TextCapitalization.words,
      ),
      _dropdown('business_type', 'Business type *', businessTypes),
      _field(
        'registration_number',
        'CIN / registration number',
        hint: 'U12345OD2015PTC012345',
        caps: TextCapitalization.characters,
      ),
      _field(
        'year_established',
        'Year established',
        hint: 'e.g. 2015',
        type: TextInputType.number,
        maxLength: 4,
      ),
      _field(
        'gstin',
        'GSTIN',
        hint: '21ABCDE1234F1Z5',
        caps: TextCapitalization.characters,
      ),
      _field(
        'pan',
        'PAN',
        hint: 'ABCDE1234F',
        caps: TextCapitalization.characters,
      ),
      _field(
        'udyam_number',
        'Udyam (MSME) number',
        hint: 'UDYAM-OD-12-1234567',
        caps: TextCapitalization.characters,
      ),
      _field(
        'website',
        'Website',
        hint: 'www.yourcompany.com',
        type: TextInputType.url,
      ),
      _field(
        'turnover',
        'Annual turnover (₹)',
        hint: 'e.g. 12157070',
        type: TextInputType.number,
        digitsOnly: true,
        maxLength: 13,
        helper: (t) {
          final words = rupeesInWords(t);
          return words.isEmpty ? null : '₹ $words';
        },
      ),
      _errorBox(),
      _nav(next: 'Continue', onNext: _step3Continue),
    ],
  );

  Widget _contactStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _filledNote([..._contactKeys, 'state']),
      _field(
        'contact_person',
        'Contact person *',
        hint: 'Full name',
        caps: TextCapitalization.words,
      ),
      _field(
        'phone',
        'Phone number * (10-digit mobile)',
        hint: '98XXXXXXXX',
        type: TextInputType.phone,
        maxLength: 10,
      ),
      _field(
        'products_services',
        'Products / services and sectors you work in',
        hint: 'e.g. Civil construction, road works, electrical installation…',
        lines: 3,
        caps: TextCapitalization.sentences,
      ),
      _field(
        'address',
        'Address *',
        hint: 'Street, area, landmark',
        caps: TextCapitalization.words,
      ),
      _field(
        'city',
        'City *',
        hint: 'Bhubaneswar',
        caps: TextCapitalization.words,
      ),
      _dropdown('state', 'State / UT *', indianStates),
      _field(
        'pincode',
        'Pincode *',
        hint: '751001',
        type: TextInputType.number,
        maxLength: 6,
      ),
      _errorBox(),
      _nav(next: 'Continue', onNext: _step4Continue),
    ],
  );

  Widget _documentsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_draft.docFiles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Already attached: ${_draft.docFiles.values.expand((f) => f).map((f) => f.name).join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      OutlinedButton.icon(
        onPressed: _busy ? null : _pickExtras,
        icon: const Icon(Icons.upload_file),
        label: const Text('Add documents (PDF, DOCX, TXT, MD)'),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'Company profile, GST / PAN / Udyam certificates, turnover statements, past work orders. 10 MB per file.',
        ),
      ),
      if (_extras.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text(
          'Name each document (optional) - it helps you and the AI tell them apart later.',
        ),
        for (final (i, e) in _extras.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: e.name,
                    decoration: InputDecoration(
                      labelText: 'Document name — ${e.file.name}',
                      hintText: e.file.name,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      setState(() => _extras.removeAt(i).name.dispose()),
                ),
              ],
            ),
          ),
      ],
      _errorBox(),
      _nav(next: 'Review', onNext: () => _next([])),
    ],
  );

  Widget _kv(String label, Object? value) {
    final v = '${value ?? ''}'.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final d = _draft.data;
    final turnover = '${d['annual_turnover_cr'] ?? ''}'.trim();
    final location = [
      d['city'],
      d['state'],
      d['pincode'],
    ].where((x) => '${x ?? ''}'.trim().isNotEmpty).join(', ');
    final have = _draft.ticked.map(signupDocLabel).join(', ');
    final files = _draft.allFiles.map((f) => f.name).join(', ');
    final existing = widget.existing != null || _created;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _kv('Email', _user?.email ?? _draft.email),
                _kv(
                  'Registered company',
                  _draft.registered == null
                      ? ''
                      : (_draft.registered! ? 'Yes' : 'No'),
                ),
                _kv('Documents you have', have.isEmpty ? 'None ticked' : have),
                _kv('Company', d['company_name']),
                _kv('Business type', d['business_type']),
                _kv('CIN / Reg. no.', d['registration_number']),
                _kv('Year established', d['year_established']),
                _kv(
                  'Annual turnover',
                  turnover.isEmpty
                      ? ''
                      : '₹ ${rupeesFromCrore(turnover)} (${rupeesInWords(rupeesFromCrore(turnover))})',
                ),
                _kv('GSTIN', d['gstin']),
                _kv('PAN', d['pan']),
                _kv('Udyam', d['udyam_number']),
                _kv('Website', d['website']),
                _kv('Contact person', d['contact_person']),
                _kv('Phone', d['phone']),
                _kv('Products / services', d['products_services']),
                _kv('Address', d['address']),
                _kv('Location', location),
                _kv(
                  'Company documents',
                  files.isEmpty ? 'No documents attached' : files,
                ),
              ],
            ),
          ),
        ),
        _errorBox(),
        _nav(
          next: _errors.any((e) => e.contains('Try again'))
              ? 'Try again'
              : (existing && widget.existing != null
                    ? 'Save profile'
                    : 'Create account'),
          onNext: _create,
        ),
      ],
    );
  }

  Widget _leadSaved() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_in_talk, size: 56),
          const SizedBox(height: 16),
          Text(
            "We'll be in touch",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks $_leadName - our team will call you to help prepare your tender documents. Once you have them, come back and sign up.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onBackToLogin,
            child: const Text('Back to log in'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_leadName != null) return Scaffold(body: SafeArea(child: _leadSaved()));
    final (title, subtitle) = _titles[_step];
    final steps = [
      _accountStep,
      _readinessStep,
      _companyStep,
      _contactStep,
      _documentsStep,
      _reviewStep,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing != null
              ? 'Complete your profile'
              : 'Create your account',
        ),
        leading: widget.existing != null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy ? null : _back,
              ),
        actions: [
          if (widget.existing != null)
            TextButton(
              onPressed: _busy ? null : widget.auth.signOut,
              child: const Text(
                'Log out',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'STEP ${_step + 1} OF $signupSteps',
                        style: const TextStyle(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (_step + 1) / signupSteps,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: AppColors.blue,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      steps[_step](),
                      const SizedBox(height: 12),
                      Text(
                        '🔒 Passwords are stored hashed, never in plain text.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black45,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(_busyText!, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
