import 'package:flutter_test/flutter_test.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/core/utils/app_format.dart';

void main() {
  group('ExpenseStatus lifecycle', () {
    test('walks the complete approval chain', () {
      String? current = ExpenseStatus.pending;
      final List<String> visited = <String>[current];
      while (true) {
        final String? next = ExpenseStatus.next(current);
        if (next == null) {
          break;
        }
        visited.add(next);
        current = next;
      }

      expect(visited, ExpenseStatus.approvalChain);
      expect(current, ExpenseStatus.adviserApproved);
      expect(ExpenseStatus.next(ExpenseStatus.adviserApproved), isNull);
      expect(ExpenseStatus.next(ExpenseStatus.rejected), isNull);
      expect(ExpenseStatus.next(ExpenseStatus.flagged), isNull);
    });

    test('reports 1-based chain steps', () {
      expect(ExpenseStatus.step(ExpenseStatus.pending), 1);
      expect(ExpenseStatus.step(ExpenseStatus.treasurerVerified), 2);
      expect(ExpenseStatus.step(ExpenseStatus.auditorChecked), 3);
      expect(ExpenseStatus.step(ExpenseStatus.presidentEndorsed), 4);
      expect(ExpenseStatus.step(ExpenseStatus.adviserApproved), 5);
      expect(ExpenseStatus.step(ExpenseStatus.rejected), 0);
      expect(ExpenseStatus.step(ExpenseStatus.flagged), 0);
    });

    test('normalises unknown and null values to Pending', () {
      expect(ExpenseStatus.normalise(null), ExpenseStatus.pending);
      expect(ExpenseStatus.normalise(''), ExpenseStatus.pending);
      expect(ExpenseStatus.normalise('treasurer_verified'),
          ExpenseStatus.treasurerVerified);
      expect(ExpenseStatus.normalise('UNKNOWN'), ExpenseStatus.pending);
    });

    test('only Adviser_Approved counts as official spend', () {
      expect(ExpenseStatus.isApproved(ExpenseStatus.adviserApproved), isTrue);
      expect(ExpenseStatus.isApproved(ExpenseStatus.presidentEndorsed), isFalse);
      expect(ExpenseStatus.isInFlight(ExpenseStatus.flagged), isFalse);
      expect(ExpenseStatus.isTerminal(ExpenseStatus.rejected), isTrue);
    });
  });

  group('AppFormat budget safety', () {
    test('clampRatio protects division by zero and negatives', () {
      expect(AppFormat.clampRatio(50, 0), 0);
      expect(AppFormat.clampRatio(50, -10), 0);
      expect(AppFormat.clampRatio(double.nan, 100), 0);
      expect(AppFormat.clampRatio(150, 100), 1);
      expect(AppFormat.clampRatio(-10, 100), 0);
      expect(AppFormat.clampRatio(87, 100), 0.87);
    });

    test('ratio keeps overspend values for warnings', () {
      expect(AppFormat.ratio(120, 100), 1.2);
      expect(AppFormat.ratio(10, 0), 0);
    });

    test('currency and percent tolerate invalid values', () {
      expect(AppFormat.currency(null), '₱0.00');
      expect(AppFormat.currency(double.infinity), '₱0.00');
      expect(AppFormat.percent(null), '0.0%');
      expect(AppFormat.percent(0.867), '86.7%');
    });
  });
}
