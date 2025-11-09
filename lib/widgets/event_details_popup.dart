import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/calendar_event.dart';

class EventDetailsPopup extends StatelessWidget {
  final DateTime date;
  final List<CalendarEvent> events;
  final bool canDelete;
  final ValueChanged<int>? onDelete; // passes eventId

  const EventDetailsPopup({
    super.key,
    required this.date,
    required this.events,
    this.canDelete = false,
    this.onDelete,
  });

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    return '$weekday, ${date.day} $month ${date.year}';
  }

  Color _getEventTypeColor(CalendarEvent event) {
    final duration = event.duration.toLowerCase();
    if (duration.contains('holiday')) {
      return const Color(0xFFEC4899); // Pink for holidays
    } else if (duration.contains('meeting')) {
      return const Color(0xFF8B5CF6); // Purple for meetings
    } else if (duration.contains('exam')) {
      return const Color(0xFFEF4444); // Red for exams
    } else {
      return const Color(0xFF10B981); // Green for general events
    }
  }

  IconData _getEventTypeIcon(CalendarEvent event) {
    final duration = event.duration.toLowerCase();
    final eventName = event.eventName.toLowerCase();
    
    if (duration.contains('holiday') || eventName.contains('holiday')) {
      return Icons.celebration;
    } else if (duration.contains('meeting') || eventName.contains('meeting')) {
      return Icons.people;
    } else if (duration.contains('exam') || eventName.contains('exam') || eventName.contains('test')) {
      return Icons.quiz;
    } else if (eventName.contains('birthday')) {
      return Icons.cake;
    } else if (eventName.contains('sports') || eventName.contains('game')) {
      return Icons.sports;
    } else {
      return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLight = theme.brightness == Brightness.light;
    const Color primaryBlue = Color(0xFF1E3A8A);
    const Color lightSurface = Color(0xFFFAFAF7);
    const Color lightBorder = Color(0xFFD9D2D0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          decoration: BoxDecoration(
            color: isLight ? lightSurface : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isLight ? lightBorder : theme.colorScheme.primary.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.3),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFEFF4FF) : primaryBlue.withValues(alpha: 0.3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Events',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isLight ? primaryBlue : Colors.white,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isLight
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                Icons.close,
                                color: isLight ? primaryBlue : Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(date),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isLight ? primaryBlue.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Events List
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: isLight ? Colors.white : Colors.transparent,
                  child: events.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No events on this date',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: events.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final eventColor = _getEventTypeColor(event);
                          final eventIcon = _getEventTypeIcon(event);
                          final Color cardBackground = isLight
                              ? eventColor.withValues(alpha: 0.08)
                              : eventColor.withValues(alpha: 0.18);
                          final Color cardBorder = isLight
                              ? eventColor.withValues(alpha: 0.2)
                              : eventColor.withValues(alpha: 0.35);
                          final Color iconBackground = isLight
                              ? eventColor.withValues(alpha: 0.18)
                              : eventColor.withValues(alpha: 0.28);
                          final Color chipBackground = isLight
                              ? eventColor.withValues(alpha: 0.18)
                              : eventColor.withValues(alpha: 0.32);
                           
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cardBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: iconBackground,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    eventIcon,
                                    color: eventColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.eventName,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      if (event.duration.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: chipBackground,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            event.duration,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: eventColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if ((event.description ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          event.description!,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Debug: Show delete button for ALL events temporarily
                                if (canDelete) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Delete event (ID: ${event.id})',
                                    onPressed: event.id != null
                                        ? () async {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Delete Event'),
                                                content: const Text('Are you sure you want to delete this event? This action cannot be undone.'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(ctx).pop(false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () => Navigator.of(ctx).pop(true),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirmed == true) {
                                              onDelete?.call(event.id!);
                                            }
                                          }
                                        : null,
                                    icon: const Icon(Icons.delete_outline),
                                    color: event.id != null
                                        ? Theme.of(context).colorScheme.error
                                        : Colors.grey,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
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
