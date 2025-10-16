import 'package:flutter/material.dart';
import '../models/task.dart';

class WeeklyCalendar extends StatefulWidget {
  final List<Task> tasks;
  final DateTime initialWeekStart;
  final Function(DateTime)? onWeekChanged;

  const WeeklyCalendar({
    Key? key,
    required this.tasks,
    required this.initialWeekStart,
    this.onWeekChanged,
  }) : super(key: key);

  @override
  State<WeeklyCalendar> createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<WeeklyCalendar> {
  late DateTime weekStart;

  @override
  void initState() {
    super.initState();
    weekStart = widget.initialWeekStart;
  }

  void _navigateWeek(int weeks) {
    setState(() {
      weekStart = weekStart.add(Duration(days: 7 * weeks));
    });
    widget.onWeekChanged?.call(weekStart);
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with navigation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _navigateWeek(-1),
                  tooltip: 'Previous week',
                ),
                Text(
                  _getMonthYearText(days),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _navigateWeek(1),
                  tooltip: 'Next week',
                ),
              ],
            ),
          ),
          
          // Days grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: days.map((day) {
                final normalizedDay = DateTime(day.year, day.month, day.day);
                final isToday = normalizedDay == today;
                final hasTask = widget.tasks.any((t) =>
                    t.dueDate != null &&
                    t.dueDate!.year == day.year &&
                    t.dueDate!.month == day.month &&
                    t.dueDate!.day == day.day);

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // Optional: Add onDayTapped callback
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isToday ? Colors.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                [day.weekday - 1],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: isToday ? Colors.white : Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "${day.day}",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isToday ? Colors.white : Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: hasTask
                                  ? (isToday ? Colors.white : Colors.red)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthYearText(List<DateTime> days) {
    final firstDay = days.first;
    final lastDay = days.last;
    
    if (firstDay.month == lastDay.month) {
      return "${_getMonthName(firstDay.month)} ${firstDay.year}";
    } else {
      return "${_getMonthName(firstDay.month)} - ${_getMonthName(lastDay.month)} ${lastDay.year}";
    }
  }

  String _getMonthName(int month) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return months[month - 1];
  }
}