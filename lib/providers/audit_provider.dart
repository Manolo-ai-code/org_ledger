import 'package:material_ui/material_ui.dart';

import '../data/models/audit_log.dart';
import '../data/repositories/audit_repository.dart';

/// Loads the append-only audit trail for the audit log screen.
class AuditProvider extends ChangeNotifier {
  AuditProvider(this._repository);

  final AuditRepository _repository;

  List<AuditLog> _logs = <AuditLog>[];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  bool _disposed = false;

  List<AuditLog> get logs => List<AuditLog>.unmodifiable(_logs);
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;

  Future<void> load({bool force = false}) async {
    if (_loading) {
      return;
    }
    if (_loadedOnce && !force) {
      return;
    }
    _loading = true;
    _error = null;
    _notify();

    try {
      _logs = await _repository.getRecent(limit: 200);
      _loadedOnce = true;
    } catch (_) {
      _error = 'The audit trail could not be loaded. Tap refresh to retry.';
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> refresh() => load(force: true);

  void reset() {
    _logs = <AuditLog>[];
    _loadedOnce = false;
    _loading = false;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
