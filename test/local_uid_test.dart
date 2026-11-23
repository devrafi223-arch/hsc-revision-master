import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('local anonymous id is a stable UUID v4 persisted in prefs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = AuthService.instance;
    await service.ensureLocalUid();
    final first = service.localUid;
    expect(first, isNotNull);
    expect(
      first,
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    // Second call returns the same id, and it is in prefs.
    await service.ensureLocalUid();
    expect(service.localUid, first);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('local-anon-uid-v1'), first);
    // With no signed-in account, the effective id is the local one.
    expect(service.effectiveUid, first);
  });
}
