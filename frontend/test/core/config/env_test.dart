import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/config/env.dart';

void main() {
  test('production refuses emulator, HTTP and credential-bearing URLs', () {
    for (final url in [
      'http://api.example.com/api/v1',
      'https://localhost/api/v1',
      'https://10.0.2.2/api/v1',
      'https://user:pass@api.example.com/api/v1'
    ]) {
      expect(() => Env.validateProductionUrl(url: url, environment: 'prod'),
          throwsStateError);
    }
    expect(
        () => Env.validateProductionUrl(
            url: 'https://coffee.example.com/api/v1', environment: 'prod'),
        returnsNormally);
    expect(
        () => Env.validateProductionUrl(
            url: 'http://10.0.2.2/api/v1', environment: 'dev'),
        returnsNormally);
  });
}
