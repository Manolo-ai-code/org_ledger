import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';

/// OrgLedger entry point.
///
/// All financial data, receipts and the audit trail live in a local SQLite
/// database, so the app starts without any network call.
///
/// On Windows, Linux and macOS the standard `sqflite` mobile plugin is not
/// available, so the FFI implementation must be initialized and registered as
/// the global database factory before any database is opened.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(OrgLedgerApp(dependencies: AppDependencies.production()));
}
