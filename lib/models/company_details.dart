/// Company profile fields and their checks - the same rules as the web app's profile page.
const businessTypes = [
  'Private Limited',
  'Public Limited',
  'LLP',
  'Partnership',
  'Proprietorship',
  'Government / PSU',
  'Other',
];

const indianStates = [
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

final _gstin = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _pan = RegExp(r'^[A-Z]{5}\d{4}[A-Z]$');
final _udyam = RegExp(r'^UDYAM-[A-Z]{2}-\d{2}-\d{7}$');
final _phone = RegExp(r'^[6-9]\d{9}$');
final _pincode = RegExp(r'^\d{6}$');

// The individual format checks (also used by the sign-up steps).
bool isValidGstin(String v) => _gstin.hasMatch(v);
bool isValidPan(String v) => _pan.hasMatch(v);
bool isValidUdyam(String v) => _udyam.hasMatch(v);
bool isValidPhone(String v) => _phone.hasMatch(v);
bool isValidPincode(String v) => _pincode.hasMatch(v);

/// 10-digit mobile from what was typed (drops +91 / 0 prefixes and separators).
String phoneDigits(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) return d.substring(2);
  if (d.length == 11 && d.startsWith('0')) return d.substring(1);
  return d;
}

const requiredFields = {
  'company_name': 'Company name',
  'business_type': 'Business type',
  'contact_person': 'Contact person',
  'phone': 'Phone number',
  'address': 'Address',
  'city': 'City',
  'state': 'State',
  'pincode': 'Pincode',
};

/// Problems with the values (already trimmed; GSTIN, PAN and Udyam upper-cased). Empty list = valid.
List<String> validateCompany(Map<String, dynamic> v) {
  String s(String k) => (v[k] ?? '').toString();
  final errors = <String>[
    for (final e in requiredFields.entries)
      if (s(e.key).isEmpty) '${e.value} is required.',
  ];
  if (s('gstin').isNotEmpty && !_gstin.hasMatch(s('gstin'))) {
    errors.add(
      'GSTIN is not valid. It has 15 characters, e.g. 22AAAAA0000A1Z5.',
    );
  }
  if (s('pan').isNotEmpty && !_pan.hasMatch(s('pan'))) {
    errors.add('PAN is not valid. It looks like ABCDE1234F.');
  }
  if (s('udyam_number').isNotEmpty && !_udyam.hasMatch(s('udyam_number'))) {
    errors.add('Udyam number is not valid. It looks like UDYAM-OD-01-0000001.');
  }
  if (s('phone').isNotEmpty && !_phone.hasMatch(s('phone'))) {
    errors.add('Phone number must be a 10-digit Indian mobile number.');
  }
  if (s('pincode').isNotEmpty && !_pincode.hasMatch(s('pincode'))) {
    errors.add('Pincode must be 6 digits.');
  }
  return errors;
}
