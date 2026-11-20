import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/company_details.dart';
import 'package:tender_agent_mobile/models/tender_documents.dart';

void main() {
  group('validateCompany', () {
    Map<String, dynamic> valid() => {
      'company_name': 'Digal',
      'business_type': 'Proprietorship',
      'contact_person': 'R',
      'phone': '9439810542',
      'address': 'A',
      'city': 'Jharsuguda',
      'state': 'Odisha',
      'pincode': '768211',
      'gstin': '21AOVPD8530K1ZQ',
      'pan': 'AOVPD8530K',
      'udyam_number': 'UDYAM-OD-14-0001245',
    };

    test(
      'accepts a complete profile',
      () => expect(validateCompany(valid()), isEmpty),
    );

    test('flags missing required and bad formats', () {
      final v = valid()
        ..['company_name'] = ''
        ..['gstin'] = 'X'
        ..['pan'] = '1'
        ..['phone'] = '123'
        ..['pincode'] = '12';
      expect(validateCompany(v).length, 5);
    });
  });

  test('phoneDigits drops +91 and leading 0', () {
    expect(phoneDigits('+91 94398-10542'), '9439810542');
    expect(phoneDigits('09439810542'), '9439810542');
  });

  group('checklist', () {
    test('registered companies also see company papers', () {
      expect(commonFor(true).length, commonFor(false).length + 2);
    });

    test('category progress counts common + own and lists what is missing', () {
      final p = categoryProgress('Manpower', false, {
        'pan_card',
        'mp_epf_esic',
      });
      expect(p.total, 10 + 4); // 10 common papers + Manpower's own 4
      expect(p.ready, 2);
      expect(p.missing, contains('Labour licence'));
      expect(p.missing, isNot(contains('PAN card')));
    });

    test('the new common documents are there and ITR + audited P&L is no longer in a category', () {
      final keys = commonFor(false).map((d) => d.key);
      expect(
        keys,
        containsAll([
          'udyam_certificate',
          'firm_registration',
          'itr_pl',
          'iso_certificate',
        ]),
      );
      for (final docs in categoryDocuments.values) {
        expect(docs.map((d) => d.label), isNot(contains('ITR + audited P&L')));
      }
    });

    test('an old per-category ITR tick becomes the common one and the old keys are dropped on save', () {
      expect(
        initialTicks(['mp_itr_pl', 'pan_card']),
        containsAll(['itr_pl', 'pan_card']),
      );
      expect(initialTicks(['pan_card']), isNot(contains('itr_pl')));
      expect(mergeTicks(['sp_itr_pl', 'udyam_old_unknown'], {'itr_pl'}), [
        'udyam_old_unknown',
        'itr_pl',
      ]);
    });

    test('saving keeps older ticks the screen does not show', () {
      final out = mergeTicks(['work_orders', 'pan_card'], {'gst_certificate'});
      expect(out, ['work_orders', 'gst_certificate']);
    });
  });
}
