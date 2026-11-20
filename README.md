# OrgLedger

Offline-first expense tracking, budgeting, role-based approvals, and A4 PDF
liquidation for student organizations.

Built with Flutter and Material 3 using local SQLite persistence. Financial
records, receipts, and audit entries stay on-device in the current build—no
bundled backend, account service, or network connection is required for core
ledger operations.

---

## Highlights

- **Offline-first local ledger.** SQLite stores `users`, `events`, `expenses`,
  `audit_logs`, and `settings`; core viewing, submission, review, and reporting
  work without connectivity.
- **Authenticated RBAC (no role switcher).** Permissions are bound to the
  signed-in account. Passwords are stored/verified as salted SHA-256 digests
  (local/offline scheme).
- **Member read-only access.** Members can view allowed records, budgets,
  reports, and audit logs but **cannot** create, add, edit, submit, approve,
  reject, or flag expenses.
- **Officer workflow actions.** Authorized officer roles can submit expenses and
  perform designated review actions by tier.
- **Five-stage approval pipeline.**
  `Pending → Treasurer_Verified → Auditor_Checked → President_Endorsed → Adviser_Approved`.
- **Mandatory remarks.** Rejecting or flagging an expense requires written
  remarks (at least 5 characters).
- **Approved-only budgeting & liquidation.** Only `Adviser_Approved` expenses
  count toward official spend, dashboard metrics, burn-down/category charts, and
  the A4 liquidation PDF. Calculations guard against invalid values (e.g.
  divide-by-zero/negative budget/NaN cases).
- **Budget event management.** Create, edit, archive/restore, and select budget
  events (starting budget and metadata) to scope expenses and reports.
- **Receipt capture & local storage.** Camera/gallery receipts are copied into
  the app’s private documents area for local access/inspection.
- **Expense-only audit trail.** Immutable, expense-linked audit records capture
  expense create/submit, stage transitions, reject/flag (with remarks), and
  expense-related liquidation/sync actions. **No login/sign-in or other
  non-expense audit records** are stored.
- **Offline sync queue (local stub).** Expenses track local sync state
  (`is_synced`); connectivity changes can trigger a flush that marks pending
  records synced locally and logs per-expense sync audit events. There is no
  bundled remote API in this build.
- **Material 3 UI.** Role-aware navigation, light/dark/system themes, status
  indicators, and charts for budget visibility.

---

## Roles and permissions

| Role | Can submit expenses | Review responsibility | Notes |
| --- | --- | --- | --- |
| Member | No | — | Read-only for expense actions |
| Business Manager | Yes | — | Officer/submitter |
| Secretary | Yes | — | Officer/submitter |
| Treasurer | Yes | `Pending` | Stage 1 verification |
| Auditor | Yes | `Treasurer_Verified` | Stage 2 audit/check |
| President | Yes | `Auditor_Checked` | Stage 3 endorsement |
| Adviser | Yes | `President_Endorsed` | Final approval + manager/admin capabilities |

Permissions are enforced by authenticated role across UI and application/data
logic. There is **no in-app role-switcher** dropdown.

---

## Expense workflow rules

1. Authorized officers submit expenses (with optional receipt) as `Pending` for
   the selected budget event.
2. Each reviewer acts only on the status assigned to their tier:
   - Treasurer: `Pending`
   - Auditor: `Treasurer_Verified`
   - President: `Auditor_Checked`
   - Adviser: `President_Endorsed`
3. Approving advances the expense to the next status; Adviser approval makes it
   `Adviser_Approved` (final/official).
4. Reject or flag actions require mandatory remarks (≥ 5 characters) and are
   recorded in the expense-only audit trail.
5. Only `Adviser_Approved` expenses are included in official spend totals,
   burn-down/category metrics, and liquidation PDF exports.

---

## Getting started

```bash
flutter pub get
flutter run
```

- **SDK:** Dart `^3.14.0` (see `pubspec.yaml`)
- **UI:** Material 3 via `package:material_ui/material_ui.dart`
- **Android package:** `com.orgledger.app`

### First-run behavior

- In normal (non-demo) mode, if no users exist, the app requires first-run setup
  to create the initial **Adviser** account before regular use.
- Session state and preferences (e.g. theme, selected event) are persisted
  locally.

### Demo data (optional)

Demo seeding and demo quick-fill accounts are **disabled by default**
(`DEMO_SEED=false`). To run a demo-seeded build:

```bash
flutter run --dart-define=DEMO_SEED=true
```

When `DEMO_SEED` is enabled, seeded demo officer accounts are available with the
password `password123` (demo login quick-fill may be shown in UI for evaluation
builds). Do not enable demo seeding for normal/production-like usage.

---

## Quality checks

```bash
flutter analyze
flutter test
```

The repository includes automated tests covering workflow/budget logic, parsing,
database/integration behavior (including FFI-backed SQLite tests where used),
and UI/widget cases.

---

## Data, offline behavior, and sync

- **Database:** local `org_ledger.db` (SQLite, schema v4) with additive
  migrations/recovery behavior.
- **Tables:** `users`, `events`, `expenses`, `audit_logs`, `settings`.
- **Receipts:** copied to the app’s private documents `receipts/` directory and
  referenced by local path.
- **Connectivity:** online/offline state is detected to inform UI and sync
  behavior.
- **Sync integration point:** `SyncService.pushRecord(...)` is the designated
  extension point for a future backend; current builds mark pending records as
  synced locally when flushed.

---

## Project structure

```
lib/
├── app.dart                     # App bootstrap, providers, auth gate, theming
├── main.dart                    # Entry point (desktop FFI setup)
├── core/
│   ├── constants/               # app constants, categories, statuses, demo accounts
│   ├── theme/                   # M3 themes/colors/visual mappings
│   └── utils/                   # formatting, validators, password hashing
├── data/
│   ├── database/                # DatabaseHelper, schema, migrations, settings
│   ├── models/                  # UserRole, AppUser, OrgEvent, Expense, AuditLog
│   ├── repositories/            # auth, expenses, audit persistence/query logic
│   └── services/                # connectivity, receipt storage, sync, PDF export
├── providers/                   # theme/session, ledger, audit state & orchestration
├── screens/
│   ├── auth/                    # setup, login, registration
│   ├── approvals/               # tier-scoped approval feed
│   ├── audit/                   # expense-only audit trail
│   ├── dashboard/               # KPIs, events, charts, export/sync actions
│   ├── expenses/                # list, add expense, inspector/receipt viewer
│   ├── home/                    # role-aware navigation shell
│   ├── members/                 # member/officer administration
│   ├── profile/                 # account, permissions, theme, sign-out
│   └── splash/
└── widgets/                     # shared UI components (cards, charts, dialogs, etc.)
```

---

## Platform configuration

**Android** (`android/app/src/main/AndroidManifest.xml`):
- Camera/network/connectivity permissions and media/read permissions as required
  for receipt capture/selection and connectivity checks.

**iOS** (`ios/Runner/Info.plist`):
- Camera and photo library usage descriptions for receipt capture/selection.

If a permission is denied, the app should continue to function where possible and
provide user-facing feedback/alternatives.

---

## Branding assets

- App logo: `assets/branding/` (declared in `pubspec.yaml`)
- In-app brand rendering: `lib/widgets/brand_mark.dart`
- Android launcher/splash assets are generated under `android/app/src/main/res/`

---

## Building a release APK (GitHub distribution)

OrgLedger is distributed as sideloadable APKs (not via Play Store).

- **Package:** `com.orgledger.app`
- **Version:** from `pubspec.yaml` (`version: 1.0.0+1`)
- **Signing:** release builds are debug-signed by default for sideloading. For
  consistent updates across machines, configure a release keystore via
  `android/key.properties` and update `android/app/build.gradle.kts` (do **not**
  commit `key.properties` or keystores).

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
# Optional: smaller per-ABI artifacts
flutter build apk --release --split-per-abi
```

Outputs are written under `build/app/outputs/flutter-apk/` (e.g.
`app-release.apk` and per-ABI APKs when split).

> **Note:** if your project path contains parentheses/spaces and the Android/Gradle
> build fails with path-related errors, run the build from a junction/symlink
> path without those characters.

---

## Data & privacy

- **Credentials:** stored locally as salted SHA-256 digests. This is appropriate
  for an offline/local app context; production deployments should use per-user
  salts and a memory-hard algorithm (e.g. Argon2id) with server-side controls.
- **On-device data:** the SQLite database and stored receipt images remain on the
  device in the current build.
- **Uninstall impact:** deleting the app removes local app data, including the
  database and stored receipt images.
- **Export:** liquidation PDFs are generated locally and only leave the device if
  the user explicitly shares/prints them via the system dialog.
- **Audit scope:** audit logging is expense-only and expense-linked (no login/sign-in records).

---

## License / notes

This repository is an academic/mobile development project. Review and adapt
security, backup, and sync integrations before any production deployment.
