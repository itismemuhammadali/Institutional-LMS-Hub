import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/calendar_event.dart';
import '../services/api_service.dart';
import 'add_event_dialog.dart';
import 'event_details_popup.dart';

class CalendarWidget extends StatefulWidget {
  final bool canAddEvents;
  final VoidCallback? onEventsChanged;
  final bool canDeleteEvents;

  const CalendarWidget({
    super.key,
    this.canAddEvents = false,
    this.onEventsChanged,
    this.canDeleteEvents = false,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<CalendarEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final result = await ApiService.getCalendarMonth(_focusedDay.year, _focusedDay.month);
      final eventsMap = <DateTime, List<CalendarEvent>>{};

      // Holidays and titles from days
      final List days = (result['days'] ?? []) as List;
      for (final d in days) {
        final dateStr = d['date'] as String?;
        if (dateStr == null) continue;
        final isHoliday = (d['is_holiday'] ?? 0) == 1;
        final title = (d['title'] ?? '') as String;
        if (isHoliday || title.isNotEmpty) {
          final dt = DateTime.parse(dateStr);
          final key = DateTime(dt.year, dt.month, dt.day);
          eventsMap.putIfAbsent(key, () => []);
          eventsMap[key]!.add(CalendarEvent(
            date: dt,
            eventName: title.isNotEmpty ? title : 'Holiday',
            duration: isHoliday ? 'Public Holiday' : 'Info',
          ));
        }
      }

      // User events - check multiple possible response formats
      List evs = [];
      if (result['events'] != null) {
        evs = result['events'] as List;
      } else if (result['data'] != null && result['data']['events'] != null) {
        evs = result['data']['events'] as List;
      } else if (result['calendar_events'] != null) {
        evs = result['calendar_events'] as List;
      }

      for (final e in evs) {
        final dateStr = e['date'] as String?;
        if (dateStr == null) continue;
        
        try {
          final dt = DateTime.parse(dateStr);
          final key = DateTime(dt.year, dt.month, dt.day);
          eventsMap.putIfAbsent(key, () => []);
          final dynamic rawId = (e['id'] ?? e['event_id'] ?? e['calendar_event_id']);
          final int? eventId = rawId is String ? int.tryParse(rawId) : (rawId is num ? rawId.toInt() : null);
          final String title = (e['title'] ?? e['name'] ?? '').toString();
          final String duration = (e['duration'] ?? e['time'] ?? 'all day').toString();
          final String? description = (e['description'] ?? e['details'] ?? e['body'])?.toString();
          eventsMap[key]!.add(CalendarEvent(
            id: eventId,
            date: dt,
            eventName: title,
            duration: duration,
            description: (description != null && description.isNotEmpty) ? description : null,
          ));
        } catch (parseError) {
          developer.log(
            'Failed to parse calendar event date',
            name: 'CalendarWidget',
            error: parseError,
          );
        }
      }

      setState(() {
        _events = eventsMap;
      });
      
      // Force calendar rebuild after events are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            // Trigger rebuild
          });
          // Notify parent that events changed
          widget.onEventsChanged?.call();
        }
      });
    } catch (e) {
      // Handle web platform or database errors gracefully
      setState(() {
        _events = <DateTime, List<CalendarEvent>>{};
      });
    }
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final events = _events[normalizedDay] ?? [];
    return events;
  }

  void _showEventDetails(DateTime day) {
    final events = _getEventsForDay(day);
    if (events.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => EventDetailsPopup(
          date: day,
          events: events,
          canDelete: widget.canDeleteEvents,
          onDelete: (eventId) async {
            try {
              final res = await ApiService.deleteCalendarEvent(eventId);
              if (res['success'] == true) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Event deleted',
                        style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onPrimary),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  );
                }
                await _loadEvents();
                // Parent listens to onEventsChanged in _loadEvents post frame callback
              } else {
                throw Exception(res['error'] ?? 'Failed to delete');
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Delete failed: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 600; // consider most phones narrow
    final dayFontSize = isNarrow ? 12.0 : 14.0;
    final indicatorSize = isNarrow ? 4.0 : 6.0;
    final rowH = isNarrow ? 44.0 : 50.0; // extra headroom prevents overflow with event dots
    final dowH = isNarrow ? 18.0 : 20.0;
    final headerTitleSize = isNarrow ? 13.0 : 14.0;
    final titleSize = isNarrow ? 17.0 : 18.0;
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    const Color accentBlue = Color(0xFF1E3A8A);

    Widget buildDayCell({
      required DateTime day,
      required bool hasEvents,
      required Color backgroundColor,
      Color? borderColor,
      double borderWidth = 1.2,
      required Color dayColor,
      bool boldDay = false,
      Color? indicatorColor,
      VoidCallback? onTap,
    }) {
      final effectiveIndicatorColor = indicatorColor ??
          (isDark ? Colors.white : theme.colorScheme.primary);

      return Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: borderColor != null
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasEvents ? onTap : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 3,
                vertical: isNarrow ? 3 : 4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: GoogleFonts.inter(
                      color: dayColor,
                      fontWeight: boldDay ? FontWeight.w700 : FontWeight.w500,
                      fontSize: dayFontSize,
                    ),
                  ),
                  if (hasEvents)
                    Padding(
                      padding: EdgeInsets.only(top: isNarrow ? 3 : 4),
                      child: Container(
                        width: indicatorSize,
                        height: indicatorSize,
                        decoration: BoxDecoration(
                          color: effectiveIndicatorColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      constraints: isNarrow ? null : const BoxConstraints(minHeight: 440),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.primary
              : const Color(0xFFD9D2D0),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Calendar',
                style: GoogleFonts.inter(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : accentBlue,
                ),
              ),
              if (widget.canAddEvents)
                ElevatedButton.icon(
                  onPressed: () async {
                    final selected = _selectedDay ?? _focusedDay;
                    final added = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => AddEventDialog(selectedDate: selected),
                    );
                    if (added == true) {
                      _loadEvents();
                      // Parent will be notified from _loadEvents post frame callback
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(
                    'Add Event',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Calendar
          TableCalendar<CalendarEvent>(
            key: ValueKey(_events.hashCode), // Force rebuild when events change
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            // Responsive heights to avoid bottom overflow on small screens
            rowHeight: rowH,
            daysOfWeekHeight: dowH,
            calendarBuilders: CalendarBuilders<CalendarEvent>(
              defaultBuilder: (context, day, focusedDay) {
                final events = _getEventsForDay(day);
                final hasEvents = events.isNotEmpty;


                return buildDayCell(
                  day: day,
                  hasEvents: hasEvents,
                  backgroundColor: hasEvents
                      ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
                      : Colors.transparent,
                  borderColor: hasEvents
                      ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.9 : 0.6)
                      : null,
                  borderWidth: isNarrow ? 1.2 : 1.4,
                  dayColor: hasEvents
                      ? theme.colorScheme.primary
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : accentBlue.withValues(alpha: 0.8)),
                  boldDay: hasEvents,
                  indicatorColor: isDark ? Colors.white : theme.colorScheme.primary,
                  onTap: () => _showEventDetails(day),
                );
              },
              todayBuilder: (context, day, focusedDay) {
                final events = _getEventsForDay(day);
                final hasEvents = events.isNotEmpty;

                return buildDayCell(
                  day: day,
                  hasEvents: hasEvents,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: hasEvents ? 0.85 : 0.65),
                  borderColor: Colors.white.withValues(alpha: 0.85),
                  borderWidth: isNarrow ? 1.4 : 1.8,
                  dayColor: Colors.white,
                  boldDay: true,
                  indicatorColor: Colors.white,
                  onTap: () => _showEventDetails(day),
                );
              },
              selectedBuilder: (context, day, focusedDay) {
                final events = _getEventsForDay(day);
                final hasEvents = events.isNotEmpty;

                return buildDayCell(
                  day: day,
                  hasEvents: hasEvents,
                  backgroundColor: theme.colorScheme.primary,
                  borderColor: Colors.white.withValues(alpha: 0.9),
                  borderWidth: isNarrow ? 1.6 : 2.0,
                  dayColor: Colors.white,
                  boldDay: true,
                  indicatorColor: Colors.white,
                  onTap: () => _showEventDetails(day),
                );
              },
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleTextStyle: GoogleFonts.inter(
                fontSize: headerTitleSize,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : accentBlue,
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: isDark ? Colors.white : accentBlue),
              rightChevronIcon: Icon(Icons.chevron_right, color: isDark ? Colors.white : accentBlue),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 0, // Disable default markers to force custom builders
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: isNarrow ? 11 : 13,
              ),
              weekendStyle: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: isNarrow ? 11 : 13,
              ),
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
              });
              // Show event details if there are events on the selected day
              _showEventDetails(selectedDay);
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
              _loadEvents();
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // No local fixed events; backend provides holidays/titles via calendar_dates.
}
