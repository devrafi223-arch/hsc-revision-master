import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/app_log.dart';

void main() {
  test('AppLog records lines and joins them as text', () {
    AppLog.clear();
    AppLog.info('test', 'hello');
    AppLog.warn('test', 'careful');
    AppLog.error('test', 'boom');
    expect(AppLog.lines.length, 3);
    expect(AppLog.text, contains('INFO test: hello'));
    expect(AppLog.text, contains('WARN test: careful'));
    expect(AppLog.text, contains('ERROR test: boom'));
  });

  test('AppLog ring buffer keeps only the last 500 lines', () {
    AppLog.clear();
    for (var i = 0; i < 510; i++) {
      AppLog.info('test', 'line $i');
    }
    expect(AppLog.lines.length, AppLog.maxLines);
    expect(AppLog.text, contains('line 509'));
    expect(AppLog.text, isNot(contains('line 0\n')));
  });

  test('AppLog.clear empties the buffer', () {
    AppLog.info('test', 'x');
    AppLog.clear();
    expect(AppLog.lines, isEmpty);
    expect(AppLog.text, isEmpty);
  });

  test('AppLog.init never throws (file sink is best-effort)', () async {
    await AppLog.init();
    AppLog.info('test', 'after init');
    expect(AppLog.lines, isNotEmpty);
  });
}
