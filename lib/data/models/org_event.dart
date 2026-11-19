/// A budgeted organization event.
class OrgEvent {
  const OrgEvent({
    required this.id,
    required this.title,
    required this.startingBudget,
  });

  final int id;
  final String title;
  final double startingBudget;

  /// Null-safe parsing with explicit casts and fallbacks.
  factory OrgEvent.fromMap(Map<String, dynamic> map) {
    return OrgEvent(
      id: _parseInt(map['id']),
      title: map['title']?.toString() ?? '',
      startingBudget: _parseDouble(map['starting_budget']),
    );
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed.toInt() : 0;
    }
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static double _parseDouble(Object? value) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0;
    }
    final double parsed = double.tryParse(value?.toString().trim() ?? '') ?? 0;
    return parsed.isFinite ? parsed : 0;
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'title': title,
      'starting_budget': startingBudget,
    };
  }

  OrgEvent copyWith({int? id, String? title, double? startingBudget}) {
    return OrgEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startingBudget: startingBudget ?? this.startingBudget,
    );
  }

  @override
  String toString() => 'OrgEvent(id: $id, title: $title, budget: $startingBudget)';
}
