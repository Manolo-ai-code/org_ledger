# OrgLedger

Offline-first expense tracking, budgeting, role-based approvals and PDF
liquidation for student organizations.

Built with Flutter, Material Design 3 and a local SQLite database. Every
receipt, expense and audit entry stays on the device — no account, no network
call and no backend are required to evaluate the app.

---

## Highlights

- **Role-bound permissions.** Six officer roles with credentials stored as salted
  SHA-256 digests. There is deliberately **no in-app role switcher**; permissions
  come from the authenticated account only.
- **Five-stage approval pipeline.**
  `Pending → Treasurer_Verified → Auditor_Checked → President_Endorsed → Adviser_Approved`.
- **Mandatory remarks.** Rejecting or flagging an expense requires a written
  reason (at least 5 characters) that is shown to the submitter.
- **Approved-only budgeting.** Only `Adviser_Approved` records affect the official
  spend, burn-down chart, category breakdown and PDF liquidation.
- **Animated burn-down.** Emerald below 80%, amber at 80%+, red at 100%+, with
  division-by-zero, negative-budget and NaN protection.
- **Receipt capture.** Camera or gallery, copied into the app's private documents
  folder so it survives cache cleanup; pinch-to-zoom receipt inspector.
- **Offline queue.** New records are saved with `is_synced = 0`, shown with an
  offline banner, and flushed automatically when connectivity returns
  (`SyncService` is a documented local stub ready for a real API).
- **One-tap PDF liquidation.** A formatted A4 report of approved expenses,
  signatures block and budget summary via the platform share sheet.
- **Audit trail.** Sign-ins, submissions, approvals, rejections, flags, syncs and
  PDF exports are appended to a read-only history.
- **Material 3 UI.** Emerald financial palette, light/dark/system themes,
  responsive cards, `fl_chart` donut and line charts, and an accessible layout.

---

## Demo accounts

All seeded accounts use the password **`password123`**.

| Role | Email | Approval tier |
| --- | --- | --- |
| Business Manager | `bm@orgledger.app` | Submitter |
| Secretary | `secretary@orgledger.app` | Submitter |
| Treasurer | `treasurer@orgledger.app` | Verifies new expenses |
| Auditor | `auditor@orgledger.app` | Audits treasurer-verified expenses |
| President | `president@orgledger.app` | Endorses audited expenses |
| Adviser | `adviser@orgledger.app` | Grants final approval |

The login screen also has quick-fill chips for each role. Signing in as different
officers in sequence is the intended way to walk an expense through the chain.

Seeded data includes **Intramurals 2026** (₱60,000 budget, ~86.7% approved spend)
and **Leadership Summit 2026** (₱25,000), plus pending, verified, endorsed,
rejected, flagged and approved examples.

---

## Getting started

```bash
flutter pub get
flutter run
```

Requires Flutter 3.50+ / Dart 3.14+. The project was developed against the
Material 3 `material_ui` package. The app targets Android and iOS, so running it
needs the Android SDK or Xcode installed.

### Quality checks

```bash
flutter analyze
flutter test
```

The test suite covers the approval lifecycle, budget-ratio guards and
bulletproof `Expense.fromMap` parsing. SQLite integration tests run the real
schema, seeder, password hashing, joins and settings on the Dart VM (via
`sqflite_common_ffi`), and narrow-screen widget tests guard login, the dashboard,
status chips and the expense inspector against overflow.

---

## Workflow rules

1. **Business Manager** and **Secretary** accounts submit expenses with receipts.
2. Each reviewer only sees and acts on the exact status of their tier:
   - Treasurer acts on `Pending`
   - Auditor acts on `Treasurer_Verified`
   - President acts on `Auditor_Checked`
   - Adviser acts on `President_Endorsed`
3. Approving forwards to the next status. The Adviser's approval is final and
   locks the record.
4. Reject/flag is terminal for the current record and always stores a remark.
5. Pending, verified, endorsed, flagged and rejected records never count toward
   official spend or the liquidation PDF.

---

## Offline model

- SQLite (`org_ledger.db`) stores `users`, `events`, `expenses`, `audit_logs`
  and `app_settings`.
- The session user id and theme mode are persisted in `app_settings`, so no
  extra dependency is needed.
- Receipts are copied to `<documents>/receipts/` before the expense is stored.
- `ConnectivityService` powers the offline banner. On an offline → online
  transition, `LedgerProvider` flushes the `is_synced = 0` queue.
- `SyncService.pushRecord` is the single integration point for a future remote
  API; this build marks local records as synced and writes an audit entry.

---

## Project structure

```
lib/
├── app.dart                     # MultiProvider, MaterialApp, AuthGate
├── main.dart                    # Entry point
├── core/
│   ├── constants/               # app constants, categories, statuses, demo users
│   ├── theme/                   # MD3 light/dark themes, colors, role visuals
│   └── utils/                   # formatting, validators, password hashing
├── data/
│   ├── database/                # schema, indexes, seeding, settings
│   ├── models/                  # AppUser, OrgEvent, Expense, AuditLog, UserRole
│   ├── repositories/            # auth, expenses, audit
│   └── services/                # connectivity, receipt storage, sync, PDF
├── providers/                   # session, ledger metrics/mutations, audit, theme
├── screens/
│   ├── auth/                    # login + registration
│   ├── approvals/               # tier-filtered approval feed
│   ├── audit/                   # read-only audit trail
│   ├── dashboard/               # KPIs, burn-down, category donut
│   ├── expenses/                # list, add expense, receipt inspector/viewer
│   ├── home/                    # role-bound bottom navigation shell
│   ├── profile/                 # permissions, theme, sign-out
│   └── splash/
└── widgets/                     # cards, charts, chips, banners, dialogs
```

---

## Platform configuration

Android (`android/app/src/main/AndroidManifest.xml`):

- `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE`
- `READ_MEDIA_IMAGES` and `READ_EXTERNAL_STORAGE` (max SDK 32)
- Camera features marked optional

iOS (`ios/Runner/Info.plist`):

- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

If a permission is denied, the app keeps working and shows a friendly message
with a gallery alternative.

---

## Data & privacy

- Passwords are hashed with a static salt + SHA-256. This is appropriate for an
  offline demo; production deployments should use a per-user salt and a
  memory-hard algorithm such as Argon2id on a server.
- Deleting the app removes the SQLite database and all stored receipt images.
- The liquidation PDF is generated locally and only leaves the device when the
  user chooses a target in the system share sheet.
