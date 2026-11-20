/// The tender-document checklist - the same keys the web app saves in `companies/{uid}.tender_documents`,
/// so ticking a document in either app shows up in the other.
class DocItem {
  const DocItem(this.key, this.label);
  final String key;
  final String label;
}

/// Added to the common papers when the bidder is a registered company.
const companyDocuments = [
  DocItem(
    'incorporation_certificate',
    'Certificate of Incorporation / firm registration',
  ),
  DocItem('moa_aoa', 'MoA & AoA / partnership deed'),
];

/// Needed for every kind of bid.
const commonDocuments = [
  DocItem('pan_card', 'PAN card'),
  DocItem('gst_certificate', 'GST registration certificate'),
  DocItem('udyam_certificate', 'Udyam (MSME) registration certificate'),
  DocItem('firm_registration', 'Firm registration certificate'),
  DocItem('itr_pl', 'ITR + audited P&L'),
  DocItem('iso_certificate', 'ISO certificate'),
  DocItem('dsc', 'Class 3 DSC'),
  DocItem('non_blacklisting', 'Non-blacklist affidavit'),
  DocItem('bank_details', 'Bank account details'),
  DocItem('turnover_certificate', 'CA turnover certificate'),
];

/// Extra papers per kind of work (category name -> documents).
const categoryDocuments = <String, List<DocItem>>{
  'Manpower': [
    DocItem('mp_epf_esic', 'EPF + ESIC challans'),
    DocItem('mp_labour_licence', 'Labour licence'),
    DocItem('mp_min_wage', 'Min. wage undertaking'),
    DocItem('mp_work_orders', 'Similar work orders'),
  ],
  'Supplies': [
    DocItem('sp_oem_auth', 'OEM authorisation'),
    DocItem('sp_specs', 'Specs / datasheets'),
    DocItem('sp_test_reports', 'Test reports / BIS'),
    DocItem('sp_warranty', 'Warranty undertaking'),
  ],
  'Civil / construction': [
    DocItem('cv_registration', 'Registration class'),
    DocItem('cv_no_relation', 'No-relation cert.'),
    DocItem('cv_litigation', 'Litigation affidavit'),
    DocItem('cv_machinery', 'Machinery proof'),
    DocItem('cv_similar_works', 'Similar works list'),
  ],
};

/// "ITR + audited P&L" used to be listed under Manpower and Supplies; it is now one common document. A saved tick
/// on either old key counts as a tick on the common one, and the old keys are dropped when the checklist is saved.
const retiredKeys = {'mp_itr_pl', 'sp_itr_pl'};

/// The saved keys as ticks for the checklist: an old per-category ITR tick becomes the common `itr_pl` tick.
Set<String> initialTicks(Iterable<String> saved) {
  final ticked = saved.toSet();
  if (ticked.any(retiredKeys.contains)) ticked.add('itr_pl');
  return ticked;
}

/// Common papers shown for the chosen answer to "Do you have a registered company?".
List<DocItem> commonFor(bool? registered) => [
  if (registered == true) ...companyDocuments,
  ...commonDocuments,
];

/// Every key this checklist shows. Saved keys outside this set (older ticks such as Udyam or ISO) are
/// kept untouched when the checklist is saved.
Set<String> get shownKeys => {
  ...companyDocuments.map((d) => d.key),
  ...commonDocuments.map((d) => d.key),
  for (final docs in categoryDocuments.values) ...docs.map((d) => d.key),
};

/// Merge ticks back into the saved list: keep keys this screen doesn't show, replace the rest.
List<String> mergeTicks(Iterable<String> saved, Set<String> ticked) => [
  ...saved.where((k) => !shownKeys.contains(k) && !retiredKeys.contains(k)),
  ...(ticked.toList()..sort()),
];

/// Ready count and missing labels for one category: common papers plus that category's own.
({int ready, int total, List<String> missing}) categoryProgress(
  String category,
  bool? registered,
  Set<String> ticked,
) {
  final docs = [...commonFor(registered), ...categoryDocuments[category]!];
  final missing = [
    for (final d in docs)
      if (!ticked.contains(d.key)) d.label,
  ];
  return (
    ready: docs.length - missing.length,
    total: docs.length,
    missing: missing,
  );
}
