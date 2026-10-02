import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDlx_p0_CMcezRpjewbQWVI1ZWHW9Zl_j0',
    appId: '1:1078627613892:web:3c424e1b08c3d9b48a9d91',
    messagingSenderId: '1078627613892',
    projectId: 'au-fee',
    authDomain: 'au-fee.firebaseapp.com',
    databaseURL: 'https://au-fee-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'au-fee.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDs6V4w-WFIA3N4UqQ1TCLGOjDL_5JCYEM',
    appId: '1:1078627613892:android:3984e239df4865468a9d91',
    messagingSenderId: '1078627613892',
    projectId: 'au-fee',
    databaseURL: 'https://au-fee-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'au-fee.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDlx_p0_CMcezRpjewbQWVI1ZWHW9Zl_j0',
    appId: '1:1078627613892:web:3c424e1b08c3d9b48a9d91',
    messagingSenderId: '1078627613892',
    projectId: 'au-fee',
    authDomain: 'au-fee.firebaseapp.com',
    databaseURL: 'https://au-fee-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'au-fee.firebasestorage.app',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBH8n1tOBFChFQBKqvHXP4yIcqw3ecXkuQ',
    appId: '1:1078627613892:ios:b8879ef3440dd2398a9d91',
    messagingSenderId: '1078627613892',
    projectId: 'au-fee',
    databaseURL: 'https://au-fee-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'au-fee.firebasestorage.app',
    androidClientId: '1078627613892-3pkc1gej7dhajs0etoj7u771fkbjkoap.apps.googleusercontent.com',
    iosClientId: '1078627613892-j90j7gc7fin4v8pta2hdf5fqndkkfndm.apps.googleusercontent.com',
    iosBundleId: 'com.example.auFee',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBH8n1tOBFChFQBKqvHXP4yIcqw3ecXkuQ',
    appId: '1:1078627613892:ios:b8879ef3440dd2398a9d91',
    messagingSenderId: '1078627613892',
    projectId: 'au-fee',
    databaseURL: 'https://au-fee-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'au-fee.firebasestorage.app',
    androidClientId: '1078627613892-3pkc1gej7dhajs0etoj7u771fkbjkoap.apps.googleusercontent.com',
    iosClientId: '1078627613892-j90j7gc7fin4v8pta2hdf5fqndkkfndm.apps.googleusercontent.com',
    iosBundleId: 'com.example.auFee',
  );
}
