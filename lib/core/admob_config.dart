class AdmobConfig {
  // Singleton pattern
  static final AdmobConfig _instance = AdmobConfig._internal();
  factory AdmobConfig() => _instance;
  AdmobConfig._internal();

  // AdMob App ID (replace with your actual App ID)
  String _appId = 'ca-app-pub-6203298272391383~6221390463';

  // Ad Unit IDs (replace with your actual Ad Unit IDs)
  
    String _banner = 'ca-app-pub-6203298272391383/8267865654';
   String _interstitial = 'ca-app-pub-6203298272391383/7833855035';
    String _rewarded = 'ca-app-pub-6203298272391383/5544798694' ;
     String _native = 'ca-app-pub-6203298272391383/7513189431' ;
    // Add more ad units as needed (e.g., 'rewarded', 'native')
  

  // Getter for App ID
  String get appId => _appId;

String get banner => _banner;
String get native => _native;
String get interstitial => _interstitial;
String get rewarded => _rewarded;
  // Getter for Ad Unit IDs
 
}