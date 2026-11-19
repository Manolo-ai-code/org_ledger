import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked receipt images into the app's private documents directory.
///
/// `image_picker` returns temporary cache paths that can be purged by the OS.
/// Persisting the bytes here guarantees the receipt remains available for the
/// auditor and for PDF exports, even when offline.
class ReceiptStorageService {
  ReceiptStorageService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  static const Set<String> _allowedExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  /// Copies [sourcePath] into `documents/receipts` and returns the new path.
  ///
  /// Throws [ReceiptStorageException] when the file cannot be read or written.
  Future<String> persistReceipt(String sourcePath) async {
    final String cleanSource = sourcePath.trim();
    if (cleanSource.isEmpty) {
      throw const ReceiptStorageException('No receipt image was selected.');
    }

    final File source = File(cleanSource);
    if (!await source.exists()) {
      throw const ReceiptStorageException(
        'That image is no longer available. Please capture it again.',
      );
    }

    try {
      final Directory documents = await _documentsDirectory();
      final Directory receipts = Directory(
        p.join(documents.path, 'receipts'),
      );
      if (!await receipts.exists()) {
        await receipts.create(recursive: true);
      }

      // Avoid copying an already-persisted receipt.
      final String normalSource = p.canonicalize(source.absolute.path);
      final String receiptRoot = p.canonicalize(receipts.absolute.path);
      if (p.isWithin(receiptRoot, normalSource)) {
        return source.absolute.path;
      }

      String extension = p.extension(cleanSource).toLowerCase();
      if (!_allowedExtensions.contains(extension)) {
        extension = '.jpg';
      }

      final String filename =
          'receipt_${DateTime.now().microsecondsSinceEpoch}$extension';
      final String destination = p.join(receipts.path, filename);
      final File copied = await source.copy(destination);
      return copied.path;
    } on ReceiptStorageException {
      rethrow;
    } on FileSystemException {
      throw const ReceiptStorageException(
        'Could not save the receipt on this device. Check available storage.',
      );
    } catch (_) {
      throw const ReceiptStorageException(
        'Could not save the receipt. Please try again.',
      );
    }
  }

  /// Best-effort removal of a receipt that is no longer referenced.
  Future<void> deleteReceipt(String? path) async {
    final String cleanPath = path?.trim() ?? '';
    if (cleanPath.isEmpty) {
      return;
    }
    try {
      final File file = File(cleanPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Losing an unreferenced cache file is not worth interrupting the user.
    }
  }

  Future<bool> exists(String? path) async {
    final String cleanPath = path?.trim() ?? '';
    if (cleanPath.isEmpty) {
      return false;
    }
    try {
      return await File(cleanPath).exists();
    } catch (_) {
      return false;
    }
  }
}

class ReceiptStorageException implements Exception {
  const ReceiptStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
