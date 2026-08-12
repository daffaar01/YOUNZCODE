import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/services/secret_scanner.dart';

void main() {
  test('menyensor kredensial dalam JSON yang dikutip', () {
    const content = '{"password": "Pr0dPassw0rd!"}';
    final redacted = SecretScanner.redact(content);
    expect(SecretScanner.containsSecret(content), isTrue);
    expect(redacted, isNot(contains('Pr0dPassw0rd!')));
    expect(redacted, contains('[REDACTED credential]'));
  });

  test('menyensor key majemuk gaya KEY=value (db_password)', () {
    const content = 'db_password=Sup3rSecretValue';
    expect(SecretScanner.containsSecret(content), isTrue);
    expect(SecretScanner.redact(content), isNot(contains('Sup3rSecretValue')));
  });

  test('mendeteksi GitHub fine-grained PAT dan AWS session key', () {
    const pat = 'github_pat_11AABBCCDD0123456789_abcdefghijklmnop';
    const asia = 'ASIAZ7ABCDEFGHIJKLMN';
    expect(SecretScanner.containsSecret(pat), isTrue);
    expect(SecretScanner.containsSecret(asia), isTrue);
    expect(SecretScanner.redact('token $pat'), isNot(contains(pat)));
    expect(SecretScanner.redact('cred $asia'), isNot(contains(asia)));
  });

  test('menyensor seluruh blok PEM private key, bukan hanya header', () {
    const key =
        '-----BEGIN RSA PRIVATE KEY-----\n'
        'MIIBOwIBAAJBAKj34GkxFhD90vcNLYLInFEXampleBodyLine\n'
        '-----END RSA PRIVATE KEY-----';
    final redacted = SecretScanner.redact(key);
    expect(redacted, isNot(contains('MIIBOwIBAAJBAKj34')));
    expect(redacted, contains('[REDACTED private key]'));
  });

  test(
    'menyensor authorization, URI credential, cookie, dan connection string',
    () {
      final samples = [
        'Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456',
        'https://admin:supersecret@example.com/database',
        'Cookie: session=abcdefghijklmnopqrstuvwxyz123456',
        'Server=db;User Id=admin;Password=SuperSecret123;',
        [
          'xox',
          'b',
          '-123456789012-',
          '123456789012-',
          'abcdefghijklmnopqrstuvwx',
        ].join(),
      ];
      for (final sample in samples) {
        expect(SecretScanner.containsSecret(sample), isTrue, reason: sample);
        expect(
          SecretScanner.redact(sample),
          isNot(equals(sample)),
          reason: sample,
        );
      }
    },
  );

  test('mendeteksi npm, Google API, dan nama credential aplikasi', () {
    const samples = [
      'npm_abcdefghijklmnopqrstuvwxyz1234567890',
      'AIzaSyA234567890abcdefghijklmnopqrstuvwxyz',
      'DATABASE_URL=postgres://user:longpassword@db.example/app',
      'PRIVATE_TOKEN_NAME=abcdefghijklmnopqrstuvwxyz123456',
      'SESSION_VALUE=abcdefghijklmnopqrstuvwxyz1234567890',
    ];
    for (final sample in samples) {
      expect(SecretScanner.containsSecret(sample), isTrue, reason: sample);
      expect(
        SecretScanner.redact(sample),
        isNot(equals(sample)),
        reason: sample,
      );
    }
  });

  test('nilai pendek non-rahasia tidak disensor', () {
    // Regression: workspace read_file test relies on SECRET=x round-tripping.
    expect(SecretScanner.redact('SECRET=x'), 'SECRET=x');
    expect(SecretScanner.containsSecret('SECRET=x'), isFalse);
  });

  test('kunci OpenAI sk- tetap disensor', () {
    const key = 'sk-abcdefghijklmnopqrstuvwxyz123456';
    expect(SecretScanner.redact('key: $key'), isNot(contains(key)));
  });
}
