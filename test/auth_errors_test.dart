import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/api_client.dart';
import 'package:hsc_revision_master/services/auth_service.dart';

void main() {
  test('DNS / network failures become a plain internet message', () {
    const raw =
        'ClientException with SocketException: Failed host lookup: \'hsc-revision-master-api.vercel.app\' (OS Error: No address associated with hostname, errno = 7), uri=https://hsc-revision-master-api.vercel.app/api/auth/send-code';
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

  test('backend error codes get plain sentences', () {
    expect(
      AuthService.friendlyError(
        ApiException('CODE_INVALID', 'Invalid code'),
      ),
      'Wrong code. Try again.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('CODE_EXPIRED', 'Code expired'),
      ),
      'The code has expired — tap Resend for a new one.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('CODE_LOCKED', 'Too many attempts'),
      ),
      'Too many wrong tries. Ask for a new code.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('TOO_SOON', 'Too soon'),
      ),
      'Wait a minute before asking for a new code.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('EMAIL_DOMAIN_NOT_ALLOWED', 'Domain not allowed'),
      ),
      'Only Gmail, Hotmail, Outlook, and Yahoo emails are allowed.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('EMAIL_NOT_CONFIGURED', 'Email not configured'),
      ),
      'Email sending is not set up on the server yet — ask the admin to set it.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('UNAUTHORIZED', 'No token'),
      ),
      'Please log in to continue.',
    );
    expect(
      AuthService.friendlyError(
        ApiException('FORBIDDEN', 'Not an admin'),
      ),
      'You are not allowed to do that.',
    );
  });

  test('unknown errors keep their message without the Exception prefix', () {
    expect(
      AuthService.friendlyError(Exception('something broke')),
      'something broke',
    );
  });
}
