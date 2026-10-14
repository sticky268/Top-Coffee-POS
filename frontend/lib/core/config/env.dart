/// Environment configuration. Values are compiled in via --dart-define,
/// e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'http://10.0.2.2:8000/api/v1', // Android emulator -> host localhost
  );

  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProd => flavor == 'prod';

  static void validateProductionUrl(
      {String url = apiBaseUrl, String environment = flavor}) {
    if (environment != 'prod') return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        ['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw StateError(
          'A production build requires an HTTPS API_BASE_URL for the production server.');
    }
  }
}
