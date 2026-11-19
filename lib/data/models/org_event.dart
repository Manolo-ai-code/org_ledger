/// A budgeted organization event (semester, school year fund, or project).
///
/// `startingBudget` is the allocation for this event; official spend against it
/// is computed elsewhere from Adviser-approved expenses only. Events are never
/// hard-deleted when they may have history; completed periods can be archived.
class OrgEvent {
  const OrgEvent({
    required this.id,
    required this.title,
    required this.startingBudget,
    this.eventType = 'General',
    this.schoolYear = '',
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String title;
  final double startingBudget;

  /// Optional label for organization (e.g. General, School Year, Semester, Project).
  final String eventType;

  /// Optional school year/term label (e.g. "SY 2026-2027 · 1st Sem").
  final String schoolYear;

  /// Archived events are hidden from the active picker by default but remain
  /// available for records and reporting.
  final bool isArchived;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Null-safe parsing with explicit casts and fallbacks.
  factory OrgEvent.fromMap(Map<String, dynamic> map) {
    return OrgEvent(
      id: _parseInt(map['id']),
      title: map['title']?.toString() ?? '',
      startingBudget: _parseDouble(map['starting_budget']),
      eventType: _cleanText(map['event_type'], fallback: 'General'),
      schoolYear: _cleanText(map['school_year']),
      isArchived: _parseBool(map['is_archived']),
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
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

  static bool _parseBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value.toInt() == 1;
    }
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true';
  }

  static DateTime? _parseDate(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static String _cleanText(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'title': title,
      'starting_budget': startingBudget,
      'event_type': eventType.trim().isEmpty ? 'General' : eventType.trim(),
      'school_year': schoolYear.trim(),
      'is_archived': isArchived ? 1 : 0,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  OrgEvent copyWith({
    int? id,
    String? title,
    double? startingBudget,
    String? eventType,
    String? schoolYear,
    bool? isArchived,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return OrgEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startingBudget: startingBudget ?? this.startingBudget,
      eventType: eventType ?? this.eventType,
      schoolYear: schoolYear ?? this.schoolYear,
      isArchived: isArchived ?? this.isArchived,
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }

  @override
  String toString() =>
      'OrgEvent(id: $id, title: $title, budget: $startingBudget, archived: $isArchived)';
}
