import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/tender.dart';
import 'package:tender_agent_mobile/widgets/tender_agent_panel.dart';

void main() {
  // The panel must fit a narrow phone with big system text: no "RIGHT OVERFLOWED BY n PIXELS" stripes.
  for (final (width, scale) in [
    (360.0, 1.0),
    (360.0, 1.3),
    (360.0, 1.5),
    (320.0, 1.3),
  ]) {
    testWidgets('panel fits at $width px, text x$scale', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(
        d.toString(minLevel: DiagnosticLevel.info).split('\n').take(8).join('\n'),
      );
      await tester.binding.setSurfaceSize(Size(width, 1400));
      final tender = Tender.fromJson({
        'id': '9394745292896075',
        'title':
            'Existing Agriculture Infrastructures And Campus Development Work',
        'department': 'Agriculture Department',
        'location': 'Odisha',
        'value_cr': 1.5,
        'match': 90,
        'risk': 'High',
        'risk_reason': 'closes today',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1400),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TenderAgentPanel(
                    tender: tender,
                    saved: false,
                    onSave: () {},
                    onRefresh: () async {},
                    onAsk: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      FlutterError.onError = previous; // put the test framework's handler back BEFORE expect()
      expect(errors, isEmpty);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  }
}
