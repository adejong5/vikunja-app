import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:vikunja_app/core/di/network_provider.dart';
import 'package:vikunja_app/data/data_sources/google_calendar_data_source.dart';
import 'package:vikunja_app/domain/entities/google_calendar_event.dart';
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
  final int? viewId;

  const ProjectCalendarView({super.key, required this.project, this.viewId});

  @override
  ConsumerState<ProjectCalendarView> createState() =>
      _ProjectCalendarViewState();
}

class _ProjectCalendarViewState extends ConsumerState<ProjectCalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<GoogleCalendarEvent>> _googleEventMap = {};
  String? _lastFetchedMonth;

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _currentMonth() =>
      '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchGoogleEvents();
    });
  }

  Future<void> _fetchGoogleEvents() async {
    final viewId = widget.viewId;
    if (viewId == null) return;

    final month = _currentMonth();
    if (month == _lastFetchedMonth) return;

    final ds = GoogleCalendarDataSource(ref.read(clientProviderProvider));
    try {
      final response = await ds.getProjectEvents(
        widget.project.id,
        viewId,
        month,
      );
      if (!mounted) return;
      if (response.isSuccessful) {
        final events = response.toSuccess().body;
        final map = <DateTime, List<GoogleCalendarEvent>>{};
        for (final event in events) {
          if (event.allDay) {
            final endDate = event.end != null
                ? _normalise(event.end!)
                : _normalise(event.start);
            var current = _normalise(event.start);
            while (!current.isAfter(endDate)) {
              (map[current] ??= []).add(event);
              current = current.add(const Duration(days: 1));
            }
          } else {
            final key = _normalise(event.start);
            (map[key] ??= []).add(event);
          }
        }
        setState(() {
          _googleEventMap = map;
          _lastFetchedMonth = month;
        });
      }
    } catch (_) {
      // Silently ignore — Google Calendar may not be enabled or linked
    }
  }

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

  List<GoogleCalendarEvent> _googleEventsForDay(DateTime day) {
    return _googleEventMap[_normalise(day)] ?? [];
  }

  String _formatDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  String _formatEventTime(GoogleCalendarEvent event) {
    return event.start.toLocal().toString().substring(11, 16);
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
        final selectedGoogleEvents = _selectedDay != null
            ? _googleEventsForDay(_selectedDay!)
            : <GoogleCalendarEvent>[];
        final noDueDateTasks = pageModel.tasks
            .where((t) => t.dueDate == null)
            .toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: TableCalendar<Object>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: ''},
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: (day) => [
                  ..._eventsForDay(eventMap, day),
                  ..._googleEventsForDay(day),
                ],
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                  _fetchGoogleEvents();
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
              if (selectedTasks.isEmpty && selectedGoogleEvents.isEmpty)
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
              else ...[
                if (selectedTasks.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final task = selectedTasks[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TaskTile(task: task, project: widget.project),
                          if (index < selectedTasks.length - 1 ||
                              selectedGoogleEvents.isNotEmpty)
                            const Divider(height: 1),
                        ],
                      );
                    }, childCount: selectedTasks.length),
                  ),
                if (selectedGoogleEvents.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final event = selectedGoogleEvents[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GoogleEventTile(
                            event: event,
                            formatTime: _formatEventTime,
                          ),
                          if (index < selectedGoogleEvents.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    }, childCount: selectedGoogleEvents.length),
                  ),
              ],
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final task = noDueDateTasks[index];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TaskTile(task: task, project: widget.project),
                      if (index < noDueDateTasks.length - 1)
                        const Divider(height: 1),
                    ],
                  );
                }, childCount: noDueDateTasks.length),
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

class _GoogleEventTile extends StatelessWidget {
  final GoogleCalendarEvent event;
  final String Function(GoogleCalendarEvent) formatTime;

  const _GoogleEventTile({required this.event, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SvgPicture.string(_kGoogleLogoSvg, width: 24, height: 24),
      title: Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: event.allDay
          ? null
          : Text(
              formatTime(event),
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }
}

const _kGoogleLogoSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
  <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
  <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
  <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
</svg>
''';
