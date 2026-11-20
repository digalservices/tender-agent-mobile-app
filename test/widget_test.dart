import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/services/auth_service.dart';

void main() {
  test('a PENDING company is not active', () {
    expect(accountStatusOf({'status': 'pending'}), AccountStatus.pending);
    expect(accountStatusOf({'status': 'PENDING'}), AccountStatus.pending);
  });

  test('ACTIVE or missing status counts as active', () {
    expect(accountStatusOf({'status': 'active'}), AccountStatus.active);
    expect(accountStatusOf({}), AccountStatus.active);
    expect(accountStatusOf(null), AccountStatus.needsProfile);
  });
}
