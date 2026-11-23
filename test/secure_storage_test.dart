import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/security/secure_local_storage.dart';

void main() {
  test('a full JSON session passes through unchanged', () {
    const session =
        '{"access_token":"eyJhbGciOiJFUzI1NiJ9.payload.sig","refresh_token":"r","user":{"id":"u1"}}';
    expect(SecureLocalStorage.storedSessionString(session), session);
  });

  test('a bare JWT is corrupt and yields null', () {
    expect(
      SecureLocalStorage.storedSessionString(
        'eyJhbGciOiJFUzI1NiIsImtpZCI6ImNiMGFmMzUxLWZjNWUtNGJiYS1iYmM5LThkYjEwNjM2NjUifQ.payload.sig',
      ),
      isNull,
    );
  });

  test('garbage and non-object JSON yield null', () {
    expect(SecureLocalStorage.storedSessionString(null), isNull);
    expect(SecureLocalStorage.storedSessionString('garbage'), isNull);
    expect(SecureLocalStorage.storedSessionString('{"access_token":'), isNull);
    expect(SecureLocalStorage.storedSessionString('[1,2,3]'), isNull);
  });
}
