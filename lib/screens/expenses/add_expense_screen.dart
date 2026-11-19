import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/utils/app_format.dart';
import '../../core/utils/validators.dart';
import '../../data/models/app_user.dart';
import '../../data/models/org_event.dart';
import '../../data/services/receipt_storage_service.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';

/// Pushes the Add Expense form and displays the provider's result message.
Future<void> openAddExpenseScreen(BuildContext context) async {
  final String? message = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (BuildContext context) => const AddExpenseScreen(),
    ),
  );
  if (!context.mounted || message == null || message.trim().isEmpty) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// New expense form with dynamic `Others` category and receipt capture.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _customCategoryController =
      TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _category;
  XFile? _receipt;
  bool _saving = false;
  String? _error;

  bool get _isOthers => _category == AppCategories.others;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _showSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    'Attach receipt',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  subtitle: const Text('Best for paper receipts'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickReceipt(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  subtitle: const Text('JPG, PNG, WEBP or HEIC'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickReceipt(ImageSource.gallery);
                  },
                ),
                if (_receipt != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Remove current receipt',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _receipt = null);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 3200,
        imageQuality: 88,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (!mounted || file == null) {
        return;
      }
      setState(() {
        _receipt = file;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final String message = error.code.toLowerCase().contains('camera')
          ? 'Camera access was denied. Enable it in system settings or choose from the gallery.'
          : 'The image picker could not open. Please try again.';
      setState(() => _error = message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _error = 'Could not read that image. Please try another file.',
      );
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final ReceiptStorageService receipts =
        context.read<ReceiptStorageService>();

    final AppUser? user = session.currentUser;
    final OrgEvent? event = ledger.selectedEvent;
    if (user == null) {
      setState(() => _error = 'Your session has expired. Please sign in again.');
      return;
    }
    if (event == null) {
      setState(() => _error = 'Select an event before adding an expense.');
      return;
    }
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    String storedReceiptPath = '';
    try {
      if (_receipt != null) {
        storedReceiptPath = await receipts.persistReceipt(_receipt?.path ?? '');
      }

      final LedgerActionResult result = await ledger.submitExpense(
        user: user,
        title: _titleController.text,
        amount: Validators.parseAmount(_amountController.text),
        category: _category ?? AppCategories.miscellaneous,
        customCategory: _customCategoryController.text,
        receiptImagePath: storedReceiptPath,
      );

      if (!mounted) {
        return;
      }
      if (!result.success) {
        setState(() {
          _error = result.message;
          _saving = false;
        });
        if (storedReceiptPath.isNotEmpty) {
          await receipts.deleteReceipt(storedReceiptPath);
        }
        return;
      }
      Navigator.of(context).pop(result.message);
    } on ReceiptStorageException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = 'The expense could not be submitted. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final OrgEvent? event = ledger.selectedEvent;
    final bool canSubmit = session.canSubmitExpenses;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Add expense'),
            Text(
              event?.title ?? 'No event selected',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: canSubmit && event != null
          ? Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _saving
                          ? 'Saving expense…'
                          : ledger.isOnline
                              ? 'Submit for approval'
                              : 'Save offline',
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: !canSubmit
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.lock_outline_rounded, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      'Submission is limited to submitters',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Only Business Manager and Secretary accounts can add expenses. '
                      'Reviewers act on items in the Approvals tab.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            SyncBanner(
                              isOnline: ledger.isOnline,
                              pendingCount: ledger.pendingSyncCount,
                              isSyncing: ledger.isSyncing,
                            ),
                            if (!ledger.isOnline)
                              const SizedBox(height: 10),
                            if (_error != null) ...<Widget>[
                              ErrorBanner(message: _error ?? ''),
                              const SizedBox(height: 10),
                            ],
                            _SectionCard(
                              title: 'Expense details',
                              subtitle:
                                  'Clear descriptions speed up verification.',
                              icon: Icons.edit_note_outlined,
                              child: Column(
                                children: <Widget>[
                                  TextFormField(
                                    controller: _titleController,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    textInputAction: TextInputAction.next,
                                    maxLength: 120,
                                    validator: Validators.expenseTitle,
                                    decoration: const InputDecoration(
                                      labelText: 'What was purchased?',
                                      hintText: 'e.g. Tarpaulin printing for opening day',
                                      prefixIcon:
                                          Icon(Icons.shopping_bag_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _amountController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.]'),
                                      ),
                                    ],
                                    validator: Validators.amount,
                                    decoration: const InputDecoration(
                                      labelText: 'Amount',
                                      hintText: '0.00',
                                      prefixText: '₱ ',
                                      prefixIcon:
                                          Icon(Icons.payments_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: _category,
                                    isExpanded: true,
                                    validator: (String? value) =>
                                        value == null || value.isEmpty
                                            ? 'Choose a category'
                                            : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                      prefixIcon:
                                          Icon(Icons.category_outlined),
                                    ),
                                    hint: const Text('Select a category'),
                                    items: AppCategories.all
                                        .map(
                                          (String category) =>
                                              DropdownMenuItem<String>(
                                            value: category,
                                            child: Row(
                                              children: <Widget>[
                                                Icon(
                                                  CategoryVisuals.icon(
                                                    category,
                                                  ),
                                                  size: 18,
                                                  color: CategoryVisuals.color(
                                                    category,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    category,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (String? value) {
                                      setState(() {
                                        _category = value;
                                        if (value != AppCategories.others) {
                                          _customCategoryController.clear();
                                        }
                                      });
                                    },
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: _isOthers
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: TextFormField(
                                              controller:
                                                  _customCategoryController,
                                              textCapitalization:
                                                  TextCapitalization.words,
                                              maxLength: 40,
                                              validator: (String? value) =>
                                                  Validators.customCategory(
                                                value,
                                                required: _isOthers,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'Custom category name',
                                                hintText: 'e.g. ID Printing',
                                                prefixIcon: Icon(
                                                  Icons.auto_awesome_outlined,
                                                ),
                                              ),
                                            ),
                                          )
                                        : const SizedBox(width: double.infinity),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _SectionCard(
                              title: 'Official receipt',
                              subtitle:
                                  'Captured images are stored privately on this device.',
                              icon: Icons.receipt_long_outlined,
                              trailing: _receipt == null
                                  ? null
                                  : IconButton(
                                      tooltip: 'Remove receipt',
                                      onPressed: () =>
                                          setState(() => _receipt = null),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (_receipt == null)
                                    _ReceiptDropZone(
                                      offline: !ledger.isOnline,
                                      onTap: _showSourceSheet,
                                    )
                                  else ...<Widget>[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Stack(
                                        children: <Widget>[
                                          Container(
                                            height: 200,
                                            width: double.infinity,
                                            color: theme.colorScheme
                                                .surfaceContainerHigh,
                                            child: Image.file(
                                              File(_receipt?.path ?? ''),
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                BuildContext context,
                                                Object error,
                                                StackTrace? stackTrace,
                                              ) {
                                                return const Center(
                                                  child: Icon(
                                                    Icons.broken_image_outlined,
                                                    size: 36,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: FilledButton.tonalIcon(
                                              onPressed: _showSourceSheet,
                                              icon: const Icon(
                                                Icons.sync_rounded,
                                                size: 17,
                                              ),
                                              label: const Text('Replace'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: <Widget>[
                                        Icon(
                                          ledger.isOnline
                                              ? Icons.cloud_done_outlined
                                              : Icons.cloud_off_outlined,
                                          size: 15,
                                          color: ledger.isOnline
                                              ? AppColors.emerald
                                              : AppColors.warning,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            ledger.isOnline
                                                ? 'Receipt attached. It will be stored with this expense.'
                                                : 'Receipt attached. Saved privately even while offline.',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.route_outlined,
                                        size: 17,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'What happens next?',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    'Your expense enters the review chain: Treasurer → Auditor → '
                                    'President → Adviser. It affects the official budget only after '
                                    'final approval.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (event != null) ...<Widget>[
                                    const SizedBox(height: 9),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            'Event budget',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          AppFormat.currency(
                                            event.startingBudget,
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            'Remaining (approved only)',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          AppFormat.currency(
                                            ledger.remainingBudget,
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: ledger.remainingBudget < 0
                                                ? theme.colorScheme.error
                                                : AppColors.emerald,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'By submitting, you confirm the receipt is authentic and the amount is accurate.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing ?? const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReceiptDropZone extends StatelessWidget {
  const _ReceiptDropZone({
    required this.offline,
    required this.onTap,
  });

  final bool offline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_a_photo_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 10),
            Text('Attach receipt photo', style: theme.textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(
              'Take a photo or pick from your gallery',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (offline) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 13,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Offline · stored locally',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
