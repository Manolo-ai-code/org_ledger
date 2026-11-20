# OrgLedger

Offline-first Flutter app for student organization expense tracking, budgeting,
role-based approvals, and A4 PDF liquidation. Core data is stored locally in
SQLite (no bundled backend).

## Key behavior

- **Offline-first:** Local SQLite (`org_ledger.db`) for users, events, expenses,
  expense-only audit logs, and settings; receipts stored in the app’s private
  documents folder.
- **Authenticated RBAC:** Permissions are bound to the signed-in account. No
  in-app role switcher. Passwords are stored/verified as salted SHA-256 digests
  (local/offline context).
- **Member access:** Members are read-only for expense actions (cannot create,
  add, edit, submit, approve, reject, or flag expenses) but can view allowed
  records, budgets, reports, and audit logs.
- **Approval workflow:** `Pending → Treasurer_Verified → Auditor_Checked → President_Endorsed → Adviser_Approved`.
  Reviewer actions are limited to the authorized role/status tier.
- **Reject/flag:** Mandatory remarks (≥ 5 characters).
- **Approved-only totals:** Only `Adviser_Approved` expenses count as official
  spend, dashboard/burn-down/category metrics, and liquidation PDF exports.
  Calculations guard against invalid numeric/budget cases.
- **Budget events:** Create, edit, archive/restore, and select events to scope
  expenses and reports.
- **Audit trail:** Expense-only and expense-linked (create/submit, stage
  transitions, reject/flag with remarks, expense-related liquidation/sync).
  No login/sign-in or other non-expense audit records.
- **Sync:** Local sync state (`is_synced`) with connectivity-aware flush behavior.
  `SyncService.pushRecord(...)` is a stub/integration point; no remote API is
  bundled.

## Roles

| Role | Expense submission | Review tier |
| --- | --- | --- |
| Member | No (read-only) | — |
| Business Manager | Yes | — |
| Secretary | Yes | — |
| Treasurer | Yes | `Pending` |
| Auditor | Yes | `Treasurer_Verified` |
| President | Yes | `Auditor_Checked` |
| Adviser | Yes | `President_Endorsed` (final) |

## Getting started

```bash
flutter pub get
flutter run
```

- Dart SDK: `^3.14.0` (see `pubspec.yaml`)
- UI: Material 3 via `package:material_ui/material_ui.dart`
- Android package: `com.orgledger.app`
- First run (non-demo): if no users exist, setup creates the initial Adviser
  account.

## Quality checks

```bash
flutter analyze
flutter test
```

## Build (GitHub sideload APK)

```bash
flutter build apk --release
# Optional
flutter build apk --release --split-per-abi
```

Outputs: `build/app/outputs/flutter-apk/`. Release builds are debug-signed by
default for sideloading. Configure a keystore for consistent updates (do not
commit signing files).

## Data & privacy

- Passwords are stored locally as salted SHA-256 digests (appropriate for this
  offline/local context; use stronger per-user/server-side auth for production).
- Database and receipts remain on-device in the current build; uninstall removes
  local app data.
- Liquidation PDFs are generated locally and leave the device only via explicit
  user share/print actions.
- Audit logging is expense-only (no login/sign-in records).