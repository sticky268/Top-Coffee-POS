/// Environment configuration. Values are compiled in via --dart-define,
/// e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1', // Android emulator -> host localhost
  );

  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProd => flavor == 'prod';
}
