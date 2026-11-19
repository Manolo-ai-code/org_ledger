/// Canonical expense categories used by the app.
///
/// [AppCategories.all] is the single source of truth for the Add Expense
/// dropdown and for validation in the provider layer.
abstract final class AppCategories {
  static const String food = 'Food & Refreshments';
  static const String printing = 'Printing & Publications';
  static const String venues = 'Venues & Rentals';
  static const String prizes = 'Prizes & Awards';
  static const String transport = 'Transport & Logistics';
  static const String supplies = 'Supplies & Materials';
  static const String miscellaneous = 'Miscellaneous';
  static const String others = 'Others';

  static const List<String> all = <String>[
    food,
    printing,
    venues,
    prizes,
    transport,
    supplies,
    miscellaneous,
    others,
  ];

  /// Returns a safe category label, falling back to [miscellaneous].
  static String normalise(String? value) {
    final String candidate = value?.trim() ?? '';
    for (final String category in all) {
      if (category.toLowerCase() == candidate.toLowerCase()) {
        return category;
      }
    }
    return candidate.isEmpty ? miscellaneous : candidate;
  }

  static bool isValid(String? value) => all.contains(value);
}
