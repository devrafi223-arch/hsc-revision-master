import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/auth_service.dart';

void main() {
  test('DNS / network failures become a plain internet message', () {
    const raw =
        'AuthRetryableFetchException(message: ClientException with SocketException: Failed host lookup: \'jlhapvzrsckmldtdgeec.supabase.co\' (OS Error: No address associated with hostname, errno = 7), uri=https://jlhapvzrsckmldtdgeec.supabase.co/auth/v1/signup, statusCode: null)';
    expect(
      AuthService.friendlyError(Exception(raw)),
      'No internet connection — check your Wi-Fi or mobile data and try again.',
    );
    expect(
      AuthService.friendlyError(Exception('SocketException: Connection refused')),
      'No internet connection — check your Wi-Fi or mobile data and try again.',
    );
  });

  test('known auth failures get plain sentences', () {
    expect(
      AuthService.friendlyError(Exception('Invalid login credentials')),
      'Wrong email or password. Try again.',
    );
    expect(
      AuthService.friendlyError(Exception('User already registered')),
      'This email already has an account — log in instead.',
    );
    expect(
      AuthService.friendlyError(Exception('Email not confirmed')),
      'Your email is not confirmed yet — check your inbox for the code.',
    );
    expect(
      AuthService.friendlyError(Exception('otp_expired')),
      'The code has expired — tap Resend for a new one.',
    );
  });

  test('unknown errors keep their message without the Exception prefix', () {
    expect(
      AuthService.friendlyError(Exception('something broke')),
      'something broke',
    );
  });
}
