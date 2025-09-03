import 'package:flutter/material.dart';
import '../models/task.dart';

class WeeklyCalendar extends StatelessWidget {
  final List<Task> tasks;
  final DateTime weekStart;

  const WeeklyCalendar({
    Key? key,
    required this.tasks,
    required this.weekStart,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, // space days evenly
        children: days.map((day) {
          final hasTask = tasks.any((t) =>
              t.dueDate != null &&
              t.dueDate!.year == day.year &&
              t.dueDate!.month == day.month &&
              t.dueDate!.day == day.day);

          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day.weekday - 1],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "${day.day}",
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (hasTask)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
