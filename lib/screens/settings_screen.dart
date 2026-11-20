import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/company_details.dart';
import '../models/signup.dart';
import '../models/tender_documents.dart';
import '../services/auth_service.dart';
import '../services/company_service.dart';
import '../widgets/asset_cards.dart';
import 'documents_screen.dart';

/// Settings = account + company profile + tender-documents checklist (same data as the web app).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.user, required this.auth});
  final User user;
  final AuthService auth;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = CompanyService();
  late Future<Map<String, dynamic>> _company = _service.load(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _company,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load your company.\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(
                      () => _company = _service.load(widget.user.uid),
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        return _SettingsBody(
          user: widget.user,
          auth: widget.auth,
          service: _service,
          company: snap.data!,
        );
      },
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.user,
    required this.auth,
    required this.service,
    required this.company,
  });
  final User user;
  final AuthService auth;
  final CompanyService service;
  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user.email ?? ''),
            subtitle: const Text('Signed in'),
            trailing: TextButton(
              onPressed: auth.signOut,
              child: const Text('Log out'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SectionTitle('Company details', Icons.apartment),
        _CompanyForm(uid: user.uid, service: service, company: company),
        const SizedBox(height: 16),
        _SectionTitle('Tender documents checklist', Icons.checklist),
        _ChecklistCard(uid: user.uid, service: service, company: company),
        const SizedBox(height: 16),
        _SectionTitle('Documents', Icons.folder_outlined),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DocumentsScreen(user: user, inline: true),
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle('Letterhead', Icons.badge_outlined),
        LetterheadCard(uid: user.uid),
        const SizedBox(height: 16),
        _SectionTitle('Signature & Seal', Icons.draw_outlined),
        SignatureSealCard(uid: user.uid),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.icon);
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
}

// ---------------------------------------------------------------- company details form

class _CompanyForm extends StatefulWidget {
  const _CompanyForm({
    required this.uid,
    required this.service,
    required this.company,
  });
  final String uid;
  final CompanyService service;
  final Map<String, dynamic> company;

  @override
  State<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<_CompanyForm> {
  static const _textFields = [
    'company_name',
    'registration_number',
    'gstin',
    'udyam_number',
    'pan',
    'contact_person',
    'phone',
    'website',
    'products_services',
    'address',
    'city',
    'pincode',
    'annual_turnover_cr',
    'year_established',
  ];

  late final Map<String, TextEditingController> _c = {
    for (final f in _textFields) f: TextEditingController(text: _initial(f)),
  };
  String? _businessType;
  String? _state;
  List<String> _errors = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bt = widget.company['business_type'];
    final st = widget.company['state'];
    _businessType = businessTypes.contains(bt) ? bt as String : null;
    _state = indianStates.contains(st) ? st as String : null;
  }

  String _initial(String field) {
    final v = widget.company[field];
    if (v == null) return '';
    if (field == 'annual_turnover_cr') return rupeesFromCrore(v);
    if (v is num && field == 'year_established') return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String f) => _c[f]!.text.trim();

  Future<void> _save() async {
    final turnover = _t('annual_turnover_cr');
    final year = _t('year_established');
    final details = <String, dynamic>{
      'company_name': _t('company_name'),
      'registration_number': _t('registration_number'),
      'gstin': _t('gstin').toUpperCase(),
      'udyam_number': _t('udyam_number').toUpperCase(),
      'pan': _t('pan').toUpperCase(),
      'contact_person': _t('contact_person'),
      'phone': phoneDigits(_t('phone')),
      'website': _t('website'),
      'products_services': _t('products_services'),
      'address': _t('address'),
      'city': _t('city'),
      'pincode': _t('pincode'),
      'business_type': _businessType,
      'state': _state,
      // typed in rupees, stored in crore like the website
      'annual_turnover_cr': turnover.isEmpty
          ? null
          : double.tryParse(croreFromRupees(turnover)),
      'year_established': year.isEmpty ? null : int.tryParse(year),
    };
    final errors = validateCompany(details);
    if (turnover.isNotEmpty && details['annual_turnover_cr'] == null) {
      errors.add('Annual turnover must be a number.');
    }
    if (year.isNotEmpty && details['year_established'] == null) {
      errors.add('Year established must be a number.');
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.service.saveDetails(widget.uid, details);
      if (mounted) _toast(context, 'Company details saved.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    String field, {
    TextInputType? type,
    TextCapitalization caps = TextCapitalization.none,
    int lines = 1,
    String? hint,
    bool rupees = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c[field],
        keyboardType: type,
        textCapitalization: caps,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        inputFormatters: rupees
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        maxLength: rupees ? 13 : null,
        onChanged: rupees ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: rupees ? '' : null,
          helperText: rupees && rupeesInWords(_c[field]!.text).isNotEmpty
              ? '₹ ${rupeesInWords(_c[field]!.text)}'
              : null,
          helperStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i,
              child: Text(i, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              'Company name *',
              'company_name',
              caps: TextCapitalization.words,
            ),
            _dropdown(
              'Business type *',
              businessTypes,
              _businessType,
              (v) => setState(() => _businessType = v),
            ),
            _field(
              'CIN / registration number',
              'registration_number',
              caps: TextCapitalization.characters,
            ),
            _field(
              'GSTIN',
              'gstin',
              caps: TextCapitalization.characters,
              hint: '22AAAAA0000A1Z5',
            ),
            _field(
              'PAN',
              'pan',
              caps: TextCapitalization.characters,
              hint: 'ABCDE1234F',
            ),
            _field(
              'Udyam (MSME) number',
              'udyam_number',
              caps: TextCapitalization.characters,
              hint: 'UDYAM-OD-01-0000001',
            ),
            _field(
              'Contact person *',
              'contact_person',
              caps: TextCapitalization.words,
            ),
            _field(
              'Phone number * (10-digit mobile)',
              'phone',
              type: TextInputType.phone,
            ),
            _field(
              'Annual turnover (₹)',
              'annual_turnover_cr',
              type: TextInputType.number,
              hint: 'e.g. 12157070',
              rupees: true,
            ),
            _field(
              'Year established',
              'year_established',
              type: TextInputType.number,
            ),
            _field('Website', 'website', type: TextInputType.url),
            _field(
              'Products / services and sectors you work in',
              'products_services',
              lines: 4,
              caps: TextCapitalization.sentences,
            ),
            _field('Address *', 'address', caps: TextCapitalization.words),
            _field('City *', 'city', caps: TextCapitalization.words),
            _dropdown(
              'State / UT *',
              indianStates,
              _state,
              (v) => setState(() => _state = v),
            ),
            _field('Pincode *', 'pincode', type: TextInputType.number),
            if (_errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errors.map((e) => '• $e').join('\n'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tender documents checklist

class _ChecklistCard extends StatefulWidget {
  const _ChecklistCard({
    required this.uid,
    required this.service,
    required this.company,
  });
  final String uid;
  final CompanyService service;
  final Map<String, dynamic> company;

  @override
  State<_ChecklistCard> createState() => _ChecklistCardState();
}

class _ChecklistCardState extends State<_ChecklistCard> {
  late bool? _registered = widget.company['registered_company'] as bool?;
  late final List<String> _saved = [
    for (final k in (widget.company['tender_documents'] as List? ?? [])) '$k',
  ];
  late final Set<String> _ticked = initialTicks(_saved);
  String _category = categoryDocuments.keys.first;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final documents = mergeTicks(_saved, _ticked.intersection(shownKeys));
      await widget.service.saveChecklist(
        widget.uid,
        registered: _registered,
        documents: documents,
      );
      if (mounted) _toast(context, 'Checklist saved.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tile(DocItem d) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: _ticked.contains(d.key),
    title: Text(d.label),
    onChanged: (on) =>
        setState(() => on == true ? _ticked.add(d.key) : _ticked.remove(d.key)),
  );

  @override
  Widget build(BuildContext context) {
    final common = commonFor(_registered);
    final commonReady = common.where((d) => _ticked.contains(d.key)).length;
    final progress = categoryProgress(_category, _registered, _ticked);
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Do you have a registered company?', style: text.bodyMedium),
            RadioGroup<bool>(
              groupValue: _registered,
              onChanged: (v) => setState(() => _registered = v),
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
            if (_registered == null)
              Text('Answer this to see your checklist.', style: text.bodySmall)
            else ...[
              const Divider(),
              Text(
                'Common to all three categories',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              for (final d in common) _tile(d),
              Text(
                '$commonReady of ${common.length} common documents ready.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Category',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in categoryDocuments.keys)
                    ChoiceChip(
                      label: Text(name),
                      selected: _category == name,
                      onSelected: (_) => setState(() => _category = name),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final d in categoryDocuments[_category]!) _tile(d),
              const SizedBox(height: 8),
              Text(
                '$_category: ${progress.ready} of ${progress.total} documents ready (common + own).',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (progress.missing.isEmpty)
                Text(
                  'Everything for ${_category.toLowerCase()} tenders is ready.',
                  style: TextStyle(color: Colors.green.shade700),
                )
              else
                Text(
                  'Missing: ${progress.missing.join(', ')}',
                  style: text.bodySmall,
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save checklist'),
            ),
          ],
        ),
      ),
    );
  }
}
