import 'package:flutter_test/flutter_test.dart';
import 'package:org_ledger/core/constants/app_categories.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/data/models/expense.dart';

void main() {
  group('Expense.fromMap', () {
    test('parses a complete row', () {
      final Expense expense = Expense.fromMap(<String, dynamic>{
        'id': 7,
        'event_id': 2,
        'title': 'Tarpaulin printing',
        'amount': 1250.5,
        'category': AppCategories.printing,
        'custom_category': '',
        'receipt_image_path': '/receipts/a.jpg',
        'status': ExpenseStatus.treasurerVerified,
        'submitted_by': 3,
        'remarks': '',
        'is_synced': 1,
        'created_at': '2026-02-01T08:30:00.000',
        'updated_at': '2026-02-02T09:00:00.000',
        'submitted_by_name': 'Bea Manalo',
        'event_title': 'Intramurals 2026',
      });

      expect(expense.id, 7);
      expect(expense.eventId, 2);
      expect(expense.amount, 1250.5);
      expect(expense.status, ExpenseStatus.treasurerVerified);
      expect(expense.isSynced, isTrue);
      expect(expense.hasReceipt, isTrue);
      expect(expense.submittedByName, 'Bea Manalo');
      expect(expense.reference, 'EXP-0007');
    });

    test('never throws on a malformed or empty row', () {
      final Expense expense = Expense.fromMap(<String, dynamic>{});

      expect(expense.id, 0);
      expect(expense.eventId, 0);
      expect(expense.title, '');
      expect(expense.amount, 0.0);
      // Missing categories fall back to Miscellaneous.
      expect(expense.category, AppCategories.miscellaneous);
      expect(expense.status, ExpenseStatus.pending);
      expect(expense.isSynced, isFalse);
      expect(expense.createdAt.millisecondsSinceEpoch, 0);
      expect(expense.createdAt.millisecondsSinceEpoch, 0);
    });

    test('tolerates numeric strings and unexpected types', () {
      final Expense expense = Expense.fromMap(<String, dynamic>{
        'id': '12',
        'event_id': '3',
        'amount': '450.25',
        'category': 'others',
        'custom_category': 'ID Printing',
        'status': 'adviser_approved',
        'is_synced': 'true',
        'created_at': 'not-a-date',
        'updated_at': null,
      });

      expect(expense.id, 12);
      expect(expense.eventId, 3);
      expect(expense.amount, 450.25);
      expect(expense.status, ExpenseStatus.adviserApproved);
      expect(expense.isSynced, isTrue);
      expect(expense.createdAt.millisecondsSinceEpoch, 0);
    });

    test('uses the custom category only when Others is selected', () {
      final Expense others = Expense.fromMap(<String, dynamic>{
        'category': AppCategories.others,
        'custom_category': '  Stage decoration ',
      });
      final Expense food = Expense.fromMap(<String, dynamic>{
        'category': AppCategories.food,
        'custom_category': 'Ignored',
      });

      expect(others.displayCategory, 'Stage decoration');
      expect(food.displayCategory, AppCategories.food);
    });

    test('derived status helpers are mutually consistent', () {
      final Expense approved = Expense(
        id: 1,
        eventId: 1,
        title: 'Venue',
        amount: 100,
        category: AppCategories.venues,
        customCategory: '',
        receiptImagePath: '',
        status: ExpenseStatus.adviserApproved,
        submittedBy: 1,
        remarks: '',
        isSynced: true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      expect(approved.isApproved, isTrue);
      expect(approved.isInFlight, isFalse);
      expect(approved.isRejected, isFalse);
      expect(approved.needsAttention, isFalse);
    });
  });
}
