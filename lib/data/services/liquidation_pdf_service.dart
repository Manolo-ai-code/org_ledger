import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/expense.dart';
import '../models/org_event.dart';

class PdfExportException implements Exception {
  const PdfExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Builds the official liquidation report.
///
/// Only expenses with status `Adviser_Approved` are ever included. This is
/// enforced here as a second line of defence in addition to the provider/query
/// filters, so a stray pending row can never appear in a printed liquidation.
class LiquidationPdfService {
  const LiquidationPdfService();

  static final NumberFormat _money = NumberFormat('#,##0.00');
  static final DateFormat _date = DateFormat('MMM d, yyyy');

  /// Creates the PDF bytes without invoking a platform print dialog.
  /// Public for testing and for future file-export integrations.
  Future<Uint8List> buildReport({
    required OrgEvent event,
    required List<Expense> expenses,
    required String preparedBy,
    String organizationName = 'Student Organization',
  }) async {
    final List<Expense> approved = expenses
        .where((Expense expense) => expense.isApproved)
        .toList()
      ..sort((Expense a, Expense b) => a.createdAt.compareTo(b.createdAt));

    final double budget = _safe(event.startingBudget);
    double total = 0;
    for (final Expense expense in approved) {
      total += _safe(expense.amount);
    }
    final double remaining = budget - total;
    final double usage = budget > 0 ? (total / budget) : 0;
    final DateTime generatedAt = DateTime.now();

    final pw.Document document = pw.Document(
      title: 'Liquidation Report - ${event.title}',
      author: preparedBy,
      creator: 'OrgLedger',
      subject: 'Approved expense liquidation',
    );

    final PdfColor emerald = PdfColor.fromHex('#0B6E5B');
    final PdfColor emeraldLight = PdfColor.fromHex('#E7F5F0');
    final PdfColor ink = PdfColor.fromHex('#15231E');
    final PdfColor muted = PdfColor.fromHex('#5A6C64');
    final PdfColor line = PdfColor.fromHex('#D7E3DD');
    final PdfColor warning = PdfColor.fromHex('#B26A00');
    final PdfColor danger = PdfColor.fromHex('#B3261E');

    pw.Widget cellText(
      String text, {
      bool bold = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
      double size = 9,
    }) {
      return pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: size,
          color: color ?? ink,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );
    }

    pw.Widget summaryTile(String label, String value, PdfColor accent) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: emeraldLight,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: line, width: 0.6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7,
                  color: muted,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget signatureBlock(String label, String name) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(height: 26),
          pw.Container(height: 0.8, color: muted),
          pw.SizedBox(height: 4),
          pw.Text(
            name.trim().isEmpty ? label : name,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          pw.Text(
            name.trim().isEmpty ? 'Name and signature' : label,
            style: pw.TextStyle(fontSize: 7, color: muted),
          ),
        ],
      );
    }

    pw.Widget tableHeader() {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: pw.BoxDecoration(
          color: emerald,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          children: <pw.Widget>[
            pw.SizedBox(width: 62, child: cellText('DATE', bold: true, color: PdfColors.white, size: 7.5)),
            pw.Expanded(child: cellText('DESCRIPTION', bold: true, color: PdfColors.white, size: 7.5)),
            pw.SizedBox(width: 96, child: cellText('CATEGORY', bold: true, color: PdfColors.white, size: 7.5)),
            pw.SizedBox(width: 82, child: cellText('SUBMITTED BY', bold: true, color: PdfColors.white, size: 7.5)),
            pw.SizedBox(width: 66, child: cellText('AMOUNT', bold: true, color: PdfColors.white, align: pw.TextAlign.right, size: 7.5)),
          ],
        ),
      );
    }

    pw.Widget tableRow(Expense expense, int index) {
      final bool shaded = index.isOdd;
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: shaded ? PdfColor.fromHex('#F7FAF8') : PdfColors.white,
          border: pw.Border(
            bottom: pw.BorderSide(color: line, width: 0.5),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.SizedBox(
              width: 62,
              child: cellText(
                expense.createdAt.millisecondsSinceEpoch > 0
                    ? _date.format(expense.createdAt.toLocal())
                    : '-',
                color: muted,
                size: 8,
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  cellText(expense.title, bold: true, size: 8.5),
                  pw.SizedBox(height: 1),
                  cellText(expense.reference, color: muted, size: 6.8),
                ],
              ),
            ),
            pw.SizedBox(
              width: 96,
              child: cellText(expense.displayCategory, size: 8),
            ),
            pw.SizedBox(
              width: 82,
              child: cellText(
                expense.submittedByName.trim().isEmpty
                    ? 'User #${expense.submittedBy}'
                    : expense.submittedByName,
                size: 8,
              ),
            ),
            pw.SizedBox(
              width: 66,
              child: cellText(
                _money.format(_safe(expense.amount)),
                bold: true,
                align: pw.TextAlign.right,
                size: 8.5,
              ),
            ),
          ],
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.only(top: 5),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: line, width: 0.6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                cellText(
                  'Generated by OrgLedger on ${_date.format(generatedAt)}',
                  color: muted,
                  size: 7,
                ),
                cellText(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  color: muted,
                  size: 7,
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: emerald,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        'ORG LEDGER',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: emeraldLight,
                          letterSpacing: 2,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'LIQUIDATION REPORT',
                        style: pw.TextStyle(
                          fontSize: 20,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      cellText(
                        organizationName,
                        color: PdfColor.fromHex('#CFE9E0'),
                        size: 9,
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: <pw.Widget>[
                      cellText(
                        event.title,
                        bold: true,
                        color: PdfColors.white,
                        align: pw.TextAlign.right,
                        size: 10,
                      ),
                      pw.SizedBox(height: 3),
                      cellText(
                        'Generated ${_date.format(generatedAt)}',
                        color: PdfColor.fromHex('#CFE9E0'),
                        align: pw.TextAlign.right,
                        size: 7.5,
                      ),
                      pw.SizedBox(height: 2),
                      cellText(
                        'Prepared by $preparedBy',
                        color: PdfColor.fromHex('#CFE9E0'),
                        align: pw.TextAlign.right,
                        size: 7.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              children: <pw.Widget>[
                summaryTile(
                  'Starting budget',
                  'PHP ${_money.format(budget)}',
                  emerald,
                ),
                summaryTile(
                  'Approved expenses',
                  'PHP ${_money.format(total)}',
                  ink,
                ),
                summaryTile(
                  remaining < 0 ? 'Overspent amount' : 'Remaining balance',
                  remaining < 0
                      ? 'PHP ${_money.format(remaining.abs())}'
                      : 'PHP ${_money.format(remaining)}',
                  remaining < 0 ? danger : emerald,
                ),
                summaryTile(
                  'Budget utilization',
                  '${(usage * 100).toStringAsFixed(1)}%',
                  usage >= 1 ? danger : (usage >= 0.8 ? warning : emerald),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      'APPROVED EXPENSE SCHEDULE',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: ink,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    cellText(
                      'Only expenses with Adviser_Approved status are included.',
                      color: muted,
                      size: 7.5,
                    ),
                  ],
                ),
                cellText(
                  '${approved.length} ${approved.length == 1 ? 'item' : 'items'}',
                  color: muted,
                  size: 8,
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            tableHeader(),
            if (approved.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: line, width: 0.6),
                ),
                child: cellText(
                  'No approved expenses yet.',
                  color: muted,
                  size: 9,
                ),
              )
            else
              ...approved.asMap().entries.map(
                    (MapEntry<int, Expense> entry) =>
                        tableRow(entry.value, entry.key),
                  ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: emeraldLight,
                border: pw.Border.all(color: line, width: 0.6),
              ),
              child: pw.Row(
                children: <pw.Widget>[
                  pw.Expanded(
                    child: cellText(
                      'TOTAL APPROVED EXPENSES',
                      bold: true,
                      color: emerald,
                      size: 8.5,
                    ),
                  ),
                  pw.SizedBox(
                    width: 90,
                    child: cellText(
                      'PHP ${_money.format(total)}',
                      bold: true,
                      color: emerald,
                      align: pw.TextAlign.right,
                      size: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F7FAF8'),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: line, width: 0.6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'CERTIFICATION',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: ink,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  cellText(
                    'The undersigned certify that the expenses listed above were incurred for '
                    '${event.title}, supported by receipts on file, and approved through the '
                    'organization\'s review workflow.',
                    color: muted,
                    size: 7.8,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(child: signatureBlock('Prepared by', preparedBy)),
                pw.SizedBox(width: 24),
                pw.Expanded(child: signatureBlock('Treasurer', '')),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(child: signatureBlock('Auditor', '')),
                pw.SizedBox(width: 24),
                pw.Expanded(child: signatureBlock('President → Adviser', '')),
              ],
            ),
          ];
        },
      ),
    );

    return document.save();
  }

  /// Builds and opens the platform share/print sheet.
  ///
  /// Returns `false` when the user cancels the share sheet.
  Future<bool> shareReport({
    required OrgEvent event,
    required List<Expense> expenses,
    required String preparedBy,
    String organizationName = 'Student Organization',
  }) async {
    try {
      final Uint8List bytes = await buildReport(
        event: event,
        expenses: expenses,
        preparedBy: preparedBy,
        organizationName: organizationName,
      );
      final String safeTitle = event.title
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      return await Printing.sharePdf(
        bytes: bytes,
        filename: 'liquidation_${safeTitle.isEmpty ? 'report' : safeTitle}.pdf',
      );
    } on PdfExportException {
      rethrow;
    } catch (_) {
      throw const PdfExportException(
        'Could not generate the liquidation PDF. Please try again.',
      );
    }
  }

  static double _safe(num? value) {
    final double parsed = (value ?? 0).toDouble();
    return parsed.isFinite ? parsed : 0;
  }
}
