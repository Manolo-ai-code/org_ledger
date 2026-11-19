import 'package:material_ui/material_ui.dart';

import '../constants/app_categories.dart';
import 'app_colors.dart';

/// Icon and accent color for an expense category.
abstract final class CategoryVisuals {
  static IconData icon(String category) {
    switch (AppCategories.normalise(category)) {
      case AppCategories.food:
        return Icons.restaurant_outlined;
      case AppCategories.printing:
        return Icons.print_outlined;
      case AppCategories.venues:
        return Icons.meeting_room_outlined;
      case AppCategories.prizes:
        return Icons.emoji_events_outlined;
      case AppCategories.transport:
        return Icons.local_shipping_outlined;
      case AppCategories.supplies:
        return Icons.inventory_2_outlined;
      case AppCategories.miscellaneous:
        return Icons.category_outlined;
      case AppCategories.others:
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  static Color color(String category) {
    final String normalised = AppCategories.normalise(category);
    final int index = AppCategories.all.indexOf(normalised);
    return AppColors.category(index < 0 ? AppCategories.all.length - 1 : index);
  }
}
