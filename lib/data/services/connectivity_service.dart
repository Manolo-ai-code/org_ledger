import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around `connectivity_plus`.
///
/// The wrapper makes the connectivity dependency easy to fake in tests and
/// keeps the `connectivity_plus` result list out of providers.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Emits `true` whenever at least one usable transport is available.
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnlineResult).distinct();

  /// One-shot connectivity probe. Defaults to online if the platform channel
  /// is unavailable, because the app is offline-first anyway.
  Future<bool> isOnline() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      return _isOnlineResult(results);
    } catch (_) {
      return true;
    }
  }

  static bool _isOnlineResult(List<ConnectivityResult> results) {
    return results.any((ConnectivityResult result) =>
        result != ConnectivityResult.none);
  }
}
