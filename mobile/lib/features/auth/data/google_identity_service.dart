import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

const googleWebClientId = String.fromEnvironment(
  'FAMILYMED_GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);

abstract interface class GoogleIdentityService {
  Future<String> getIdToken();
  Future<void> signOut();
}

class PlatformGoogleIdentityService implements GoogleIdentityService {
  static Future<void>? _initialize;

  Future<void> _ensureInitialized() async {
    if (googleWebClientId.isEmpty) {
      throw StateError('Google sign-in is not configured.');
    }
    await (_initialize ??=
        GoogleSignIn.instance.initialize(serverClientId: googleWebClientId));
  }

  @override
  Future<String> getIdToken() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw StateError('No Google identity token was returned.');
    }
    return token;
  }

  @override
  Future<void> signOut() async {
    if (_initialize != null) {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    }
  }
}

final googleIdentityServiceProvider = Provider<GoogleIdentityService>(
  (ref) => PlatformGoogleIdentityService(),
);
