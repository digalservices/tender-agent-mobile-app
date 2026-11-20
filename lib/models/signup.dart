import 'dart:typed_data';

import 'company_details.dart';

/// The sign-up wizard - the same six steps, checklist and rules as the website's.
const signupSteps = 6;
const minPassword = 8;
const maxSignupFileBytes = 10 * 1024 * 1024;
const signupFileTypes = ['pdf', 'docx', 'txt', 'md'];

/// Documents tenders usually ask for. Same keys and labels as the website's sign-up checklist, so ticks
/// carry over between the apps. `companyOnly` ones are shown only to a registered company.
class SignupDoc {
  const SignupDoc(this.key, this.label, {this.companyOnly = false});
  final String key;
  final String label;
  final bool companyOnly;
}

const signupDocuments = [
  SignupDoc(
    'incorporation_certificate',
    'Certificate of Incorporation / firm registration',
    companyOnly: true,
  ),
  SignupDoc('moa_aoa', 'MoA & AoA / partnership deed', companyOnly: true),
  SignupDoc('pan_card', 'PAN card'),
  SignupDoc('gst_certificate', 'GST registration certificate'),
  SignupDoc('udyam_certificate', 'Udyam (MSME) registration certificate'),
  SignupDoc('itr', 'Income tax returns (last 3 years)'),
  SignupDoc('audited_financials', 'Audited balance sheet & P&L (last 3 years)'),
  SignupDoc('turnover_certificate', 'CA certificate of annual turnover'),
  SignupDoc('work_orders', 'Past work orders / completion certificates'),
  SignupDoc('dsc', 'Digital Signature Certificate (Class 3)'),
  SignupDoc('solvency_certificate', 'Bank solvency certificate'),
  SignupDoc('bank_details', 'Cancelled cheque / bank account details'),
  SignupDoc('epf_esic', 'EPF / ESIC registration'),
  SignupDoc('trade_licence', 'Trade licence / labour licence'),
  SignupDoc('iso_certificate', 'ISO / quality certifications'),
  SignupDoc('authorisation_letter', 'Power of attorney / authorisation letter'),
  SignupDoc('non_blacklisting', 'Non-blacklisting affidavit / declaration'),
  SignupDoc('startup_certificate', 'Startup India (DPIIT) recognition'),
];

List<SignupDoc> signupDocumentsFor(bool? registered) => [
  for (final d in signupDocuments)
    if (registered == true || !d.companyOnly) d,
];

String signupDocLabel(String key) =>
    signupDocuments.firstWhere((d) => d.key == key).label;

/// A file chosen in the wizard, kept in memory until the account is created.
class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

String _extension(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i);
}

/// A ticked document is stored under its checklist label ("PAN card.pdf"), so the AI and the bid documents'
/// enclosures can tell which file is which.
String docFileName(String label, String original, [int number = 1]) =>
    label.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-') +
    (number == 1 ? '' : ' ($number)') +
    _extension(original);

/// The stored name: `custom` (kept to the original extension) if given, else `original` unchanged.
String namedFile(String original, String custom) {
  final c = custom.trim();
  if (c.isEmpty) return original;
  final ext = _extension(original);
  return ext.isNotEmpty && c.toLowerCase().endsWith(ext.toLowerCase())
      ? c
      : c + ext;
}

/// Turnover is typed in rupees but stored in crore (as the website does).
String croreFromRupees(String rupees) {
  final digits = rupees.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final crore = BigInt.parse(digits).toDouble() / 1e7;
  return crore.toString();
}

String rupeesFromCrore(Object? crore) {
  final v = double.tryParse('${crore ?? ''}'.trim());
  return v == null ? '' : (v * 1e7).round().toString();
}

/// "12 lakh 15 thousand 70 rupees" for a rupee amount (Indian units); '' when empty.
String rupeesInWords(String rupees) {
  final digits = rupees.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  var n = BigInt.parse(digits).toInt();
  if (n == 0) return '0 rupees';
  final parts = <String>[];
  void take(int unit, String name) {
    final q = n ~/ unit;
    if (q > 0) parts.add('$q $name');
    n %= unit;
  }

  take(10000000, 'crore');
  take(100000, 'lakh');
  take(1000, 'thousand');
  take(100, 'hundred');
  if (n > 0) parts.add('$n');
  return '${parts.join(' ')} rupees';
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

List<String> validateAccount(String email, String password, String confirm) => [
  if (!_email.hasMatch(email)) 'Enter a valid email address.',
  if (password.length < minPassword)
    'Password must be at least $minPassword characters.'
  else if (password != confirm)
    'The two passwords do not match.',
];

List<String> validateFile(String name, int size) {
  if (size == 0) return ['$name is empty.'];
  if (size > maxSignupFileBytes) {
    return ['$name is larger than ${maxSignupFileBytes ~/ (1024 * 1024)} MB.'];
  }
  return [];
}

/// Step 3 - company details.
List<String> validateCompanyStep(Map<String, dynamic> v) {
  String s(String k) => '${v[k] ?? ''}'.trim();
  return [
    if (s('company_name').isEmpty) 'Company name is required.',
    if (s('business_type').isEmpty) 'Select a business type.',
    if (s('gstin').isNotEmpty && !isValidGstin(s('gstin')))
      'GSTIN looks invalid (e.g. 21ABCDE1234F1Z5).',
    if (s('pan').isNotEmpty && !isValidPan(s('pan')))
      'PAN looks invalid (e.g. ABCDE1234F).',
    if (s('udyam_number').isNotEmpty && !isValidUdyam(s('udyam_number')))
      'Udyam number looks invalid (e.g. UDYAM-OD-12-1234567).',
    if (s('year_established').isNotEmpty && !_validYear(s('year_established')))
      'Year established must be between 1800 and ${DateTime.now().year}.',
    if (s('annual_turnover_cr').isNotEmpty &&
        double.tryParse(s('annual_turnover_cr')) == null)
      'Annual turnover must be a number.',
  ];
}

bool _validYear(String s) {
  final y = int.tryParse(s);
  return y != null && y >= 1800 && y <= DateTime.now().year;
}

/// Step 4 - contact and address.
List<String> validateContactStep(Map<String, dynamic> v) {
  String s(String k) => '${v[k] ?? ''}'.trim();
  return [
    if (s('contact_person').isEmpty) 'Contact person is required.',
    if (!isValidPhone(phoneDigits(s('phone'))))
      'Enter a valid 10-digit mobile number.',
    if (s('address').isEmpty) 'Address is required.',
    if (s('city').isEmpty) 'City is required.',
    if (s('state').isEmpty) 'Select a state / UT.',
    if (!isValidPincode(s('pincode'))) 'Pincode must be 6 digits.',
  ];
}

/// Everything typed in the wizard so far (kept until the account is created).
class SignupDraft {
  String email = '';
  String password = '';
  String confirm = '';
  bool? registered;
  final Set<String> ticked = {};
  final Map<String, List<PickedFile>> docFiles =
      {}; // checklist key -> the files uploaded for it (one or more)
  final List<PickedFile> extraFiles = []; // step 5, optional
  final Map<String, dynamic> data = {}; // company + contact fields, as typed
  final Map<String, String> autofilled =
      {}; // fields filled from the documents, for the green ticks

  /// What the server stores: the typed fields plus the checklist answers, in the website's shapes.
  Map<String, dynamic> details() {
    String s(String k) => '${data[k] ?? ''}'.trim();
    return {
      'company_name': s('company_name'),
      'business_type': s('business_type'),
      'registration_number': s('registration_number'),
      'year_established': s('year_established'),
      'gstin': s('gstin').toUpperCase(),
      'pan': s('pan').toUpperCase(),
      'udyam_number': s('udyam_number').toUpperCase(),
      'website': s('website'),
      'annual_turnover_cr': s('annual_turnover_cr'),
      'contact_person': s('contact_person'),
      'phone': phoneDigits(s('phone')),
      'products_services': s('products_services'),
      'address': s('address'),
      'city': s('city'),
      'state': s('state'),
      'pincode': s('pincode'),
      'registered_company': registered,
      'tender_documents': ticked.toList()..sort(),
    };
  }

  /// Every file to upload: the ticked documents' files first, then the extra ones.
  List<PickedFile> get allFiles => [
    ...docFiles.values.expand((files) => files),
    ...extraFiles,
  ];

  /// Fills still-empty fields from values read out of the documents; never overwrites what was typed.
  void applyAutofill(Map<String, dynamic> found) {
    found.forEach((key, value) {
      if ('${data[key] ?? ''}'.trim().isEmpty && '$value'.trim().isNotEmpty) {
        data[key] = '$value';
        autofilled[key] = '$value';
      }
    });
  }

  /// Dropping a tick drops its file; ticks that are no longer offered (registered -> No) are dropped too.
  void syncTicks() {
    final allowed = {for (final d in signupDocumentsFor(registered)) d.key};
    ticked.removeWhere((k) => !allowed.contains(k));
    docFiles.removeWhere((k, _) => !ticked.contains(k));
  }
}
