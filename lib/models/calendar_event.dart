class CalendarEvent {
  final int? id;
  final DateTime date;
  final String eventName;
  final String duration;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CalendarEvent({
    this.id,
    required this.date,
    required this.eventName,
    required this.duration,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'eventName': eventName,
      'duration': duration,
      if (description != null) 'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id'],
      date: DateTime.parse(map['date']),
      eventName: map['eventName'],
      duration: map['duration'],
      description: map['description'],
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  CalendarEvent copyWith({
    int? id,
    DateTime? date,
    String? eventName,
    String? duration,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      date: date ?? this.date,
      eventName: eventName ?? this.eventName,
      duration: duration ?? this.duration,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
