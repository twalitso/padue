class AdmobConfig {
  // Singleton pattern
  static final AdmobConfig _instance = AdmobConfig._internal();
  factory AdmobConfig() => _instance;
  AdmobConfig._internal();

  // AdMob App ID (replace with your actual App ID)
  String _appId = 'ca-app-pub-6203298272391383~6221390463';

  // Ad Unit IDs (replace with your actual Ad Unit IDs)
  Map<String, String> _adUnitIds = {
    'banner': 'ca-app-pub-6203298272391383/8267865654',
    'interstitial': 'ca-app-pub-6203298272391383/7833855035',
    'rewarded':'ca-app-pub-6203298272391383/5544798694',
    // Add more ad units as needed (e.g., 'rewarded', 'native')
  };

  // Getter for App ID
  String get appId => _appId;

  // Getter for Ad Unit IDs
  String? getAdUnitId(String key) => _adUnitIds[key];

  // Optional: Setters (if you need to update dynamically)
  void setAppId(String id) => _appId = id;
  void setAdUnitId(String key, String id) => _adUnitIds[key] = id;

  // Optional: Clear method
  void clear() {
    _appId = '';
    _adUnitIds.clear();
  }
}