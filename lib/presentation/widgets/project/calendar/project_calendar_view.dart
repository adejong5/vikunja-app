import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:vikunja_app/core/di/network_provider.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/manager/project_controller.dart';
import 'package:vikunja_app/presentation/pages/error_widget.dart';
import 'package:vikunja_app/presentation/pages/loading_widget.dart';
import 'package:vikunja_app/presentation/pages/task/task_edit_page.dart';
import 'package:vikunja_app/presentation/widgets/task/add_task_dialog.dart';
import 'package:vikunja_app/presentation/widgets/task_bottom_sheet.dart';

class ProjectCalendarView extends ConsumerStatefulWidget {
  final Project project;

  const ProjectCalendarView({super.key, required this.project});

  @override
  ConsumerState<ProjectCalendarView> createState() =>
      _ProjectCalendarViewState();
}

class _ProjectCalendarViewState extends ConsumerState<ProjectCalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Map<DateTime, List<Task>> _buildEventMap(List<Task> tasks) {
    final map = <DateTime, List<Task>>{};
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null) continue;
      final key = _normalise(due);
      (map[key] ??= []).add(task);
    }
    return map;
  }

  List<Task> _eventsForDay(Map<DateTime, List<Task>> map, DateTime day) {
    return map[_normalise(day)] ?? [];
  }

  String _formatDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  Future<void> _addTask(
    BuildContext context,
    WidgetRef ref,
    DateTime dueDate,
  ) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AddTaskDialog(
        initialDueDate: dueDate,
        onAddTask: (title, due) async {
          final task = Task(
            title: title,
            dueDate: due,
            createdBy: currentUser,
            done: false,
            projectId: widget.project.id,
          );
          await ref
              .read(projectControllerProvider(widget.project).notifier)
              .addTask(widget.project, task);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(
      projectControllerProvider(widget.project),
    );

    return controllerState.when(
      loading: () => const LoadingWidget(),
      error: (err, _) => VikunjaErrorWidget(
        error: err,
        onRetry: () => ref
            .read(projectControllerProvider(widget.project).notifier)
            .reload(),
      ),
      data: (pageModel) {
        final eventMap = _buildEventMap(pageModel.tasks);
        final selectedTasks = _selectedDay != null
            ? _eventsForDay(eventMap, _selectedDay!)
            : <Task>[];
        final noDueDateTasks =
            pageModel.tasks.where((t) => t.dueDate == null).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TableCalendar<Task>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: ''},
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: (day) => _eventsForDay(eventMap, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  markerDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),

            // — Selected-day section —
            if (_selectedDay != null) ...[
              _SliverSectionHeader(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(context, _selectedDay!),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _addTask(context, ref, _selectedDay!),
                    ),
                  ],
                ),
              ),
              if (selectedTasks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      AppLocalizations.of(context).noTasksForDay,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final task = selectedTasks[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TaskTile(task: task, project: widget.project),
                          if (index < selectedTasks.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    },
                    childCount: selectedTasks.length,
                  ),
                ),
              const SliverToBoxAdapter(child: Divider(height: 8, thickness: 4)),
            ],

            // — No due date section —
            if (noDueDateTasks.isNotEmpty) ...[
              _SliverSectionHeader(
                child: Text(
                  AppLocalizations.of(context).noDueDate,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final task = noDueDateTasks[index];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TaskTile(task: task, project: widget.project),
                        if (index < noDueDateTasks.length - 1)
                          const Divider(height: 1),
                      ],
                    );
                  },
                  childCount: noDueDateTasks.length,
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }
}

class _SliverSectionHeader extends StatelessWidget {
  final Widget child;

  const _SliverSectionHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: child,
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final Task task;
  final Project project;

  const _TaskTile({required this.task, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Checkbox(
        value: task.done,
        onChanged: (_) async {
          final success = await ref
              .read(projectControllerProvider(project).notifier)
              .markAsDone(task);
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).failedToMarkDone),
              ),
            );
          }
        },
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: task.done
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
        ),
        builder: (_) => TaskBottomSheet(
          task: task,
          onEdit: () => Navigator.push<Task?>(
            context,
            MaterialPageRoute(builder: (_) => TaskEditPage(task: task)),
          ),
        ),
      ),
    );
  }
}
