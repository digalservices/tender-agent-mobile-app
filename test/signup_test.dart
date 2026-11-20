import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/signup.dart';

void main() {
  turnoverTests();
  test('account step checks email and passwords', () {
    expect(validateAccount('a@b.com', 'password1', 'password1'), isEmpty);
    expect(validateAccount('bad', 'password1', 'password1'), hasLength(1));
    expect(validateAccount('a@b.com', 'short', 'short'), hasLength(1));
    expect(validateAccount('a@b.com', 'password1', 'password2'), hasLength(1));
  });

  test('registered company sees company-only documents', () {
    final yes = signupDocumentsFor(true).length;
    final no = signupDocumentsFor(false).length;
    expect(yes, signupDocuments.length);
    expect(no, lessThan(yes));
  });

  test('file names and validation', () {
    expect(docFileName('PAN card', 'scan.pdf'), 'PAN card.pdf');
    expect(docFileName('A/B', 'x.docx'), 'A-B.docx');
    // a document with several files: the first keeps the name, the rest are numbered
    expect(docFileName('PAN card', 'a.pdf', 1), 'PAN card.pdf');
    expect(docFileName('PAN card', 'b.docx', 2), 'PAN card (2).docx');
    expect(docFileName('PAN card', 'c.pdf', 3), 'PAN card (3).pdf');
    expect(namedFile('a.pdf', ''), 'a.pdf');
    expect(namedFile('a.pdf', 'Work order'), 'Work order.pdf');
    expect(namedFile('a.pdf', 'Work order.pdf'), 'Work order.pdf');
    expect(validateFile('a.pdf', 0), isNotEmpty);
    expect(validateFile('a.pdf', maxSignupFileBytes + 1), isNotEmpty);
    expect(validateFile('a.pdf', 100), isEmpty);
  });

  test('company and contact steps', () {
    expect(validateCompanyStep({}), hasLength(2));
    expect(
      validateCompanyStep({'company_name': 'Acme', 'business_type': 'Pvt Ltd'}),
      isEmpty,
    );
    expect(
      validateCompanyStep({
        'company_name': 'Acme',
        'business_type': 'x',
        'pan': 'nope',
      }),
      hasLength(1),
    );
    expect(validateContactStep({}), hasLength(6));
    expect(
      validateContactStep({
        'contact_person': 'A',
        'phone': '9876543210',
        'address': 'x',
        'city': 'y',
        'state': 'Odisha',
        'pincode': '751001',
      }),
      isEmpty,
    );
  });

  test(
    'draft: autofill never overwrites typed values; ticks follow answer',
    () {
      final d = SignupDraft()..data['company_name'] = 'Typed';
      d.applyAutofill({'company_name': 'Read', 'pan': 'ABCDE1234F'});
      expect(d.data['company_name'], 'Typed');
      expect(d.data['pan'], 'ABCDE1234F');
      expect(d.autofilled.containsKey('company_name'), isFalse);

      d.registered = true;
      d.ticked.addAll(['incorporation_certificate', 'pan_card']);
      d.docFiles['incorporation_certificate'] = [
        PickedFile('c.pdf', Uint8List(1)),
      ];
      d.registered = false;
      d.syncTicks();
      expect(d.ticked, {'pan_card'});
      expect(d.docFiles, isEmpty);
      expect(d.details()['tender_documents'], ['pan_card']);
    },
  );

  test('a document can have several files and all of them are uploaded', () {
    final d = SignupDraft();
    d.docFiles['pan_card'] = [
      PickedFile('PAN card.pdf', Uint8List(1)),
      PickedFile('PAN card (2).pdf', Uint8List(2)),
    ];
    d.docFiles['gst_certificate'] = [PickedFile('GST.pdf', Uint8List(3))];
    d.extraFiles.add(PickedFile('profile.pdf', Uint8List(4)));
    expect(d.allFiles.map((f) => f.name), [
      'PAN card.pdf',
      'PAN card (2).pdf',
      'GST.pdf',
      'profile.pdf',
    ]);
  });
}

void turnoverTests() {
  test('turnover rupees <-> crore and words', () {
    expect(rupeesInWords('1215070'), '12 lakh 15 thousand 70 rupees');
    expect(rupeesInWords('200000000'), '20 crore rupees');
    expect(rupeesInWords(''), '');
    expect(croreFromRupees('20000000'), '2.0');
    expect(rupeesFromCrore('12.5'), '125000000');
    expect(rupeesFromCrore(''), '');
  });
}
