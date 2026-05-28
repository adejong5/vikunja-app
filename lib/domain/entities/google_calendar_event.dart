class GoogleCalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String calendarName;

  GoogleCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    required this.allDay,
    required this.calendarName,
  });

  factory GoogleCalendarEvent.fromJson(Map<String, dynamic> json) {
    final endRaw = json['end'] as String?;
    return GoogleCalendarEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      start: DateTime.parse(json['start'] as String),
      end: (endRaw != null && endRaw.isNotEmpty) ? DateTime.parse(endRaw) : null,
      allDay: json['all_day'] as bool? ?? false,
      calendarName: json['calendar_name'] as String? ?? '',
    );
  }
}
