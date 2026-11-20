/// Where the Tender Mitra backend (api.py) runs.
///
/// Override at run time:  flutter run --dart-define=API_URL=http://192.168.1.20:8000
///  - Chrome on this PC ........ http://localhost:8000 (default)
///  - Android emulator ......... http://10.0.2.2:8000
///  - Real phone on your WiFi .. http://YOUR-PC-WIFI-ADDRESS:8000
///  - Live ..................... the Railway address, once deployed
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8000',
);
