import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:vikunja_app/core/di/network_provider.dart';
import 'package:vikunja_app/core/di/repository_provider.dart';
import 'package:vikunja_app/data/data_sources/google_calendar_data_source.dart';
import 'package:vikunja_app/domain/entities/google_calendar_event.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/pages/error_widget.dart';
import 'package:vikunja_app/presentation/pages/loading_widget.dart';
import 'package:vikunja_app/presentation/pages/task/task_edit_page.dart';
import 'package:vikunja_app/presentation/widgets/task_bottom_sheet.dart';

class AllProjectsCalendarPage extends ConsumerStatefulWidget {
  const AllProjectsCalendarPage({super.key});

  @override
  ConsumerState<AllProjectsCalendarPage> createState() =>
      _AllProjectsCalendarPageState();
}

class _AllProjectsCalendarPageState
    extends ConsumerState<AllProjectsCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  bool _loading = true;
  Object? _error;
  List<Task> _tasks = [];
  Map<int, Project> _projectMap = {};
  Map<DateTime, List<GoogleCalendarEvent>> _googleEventMap = {};
  String? _lastFetchedMonth;

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _currentMonth() =>
      '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await Future.wait([_loadTasks(), _loadProjects(), _loadGoogleEvents()]);

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadTasks() async {
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    final filter = "due_date >= '$startIso' && due_date < '$endIso'";

    try {
      final response = await ref
          .read(taskRepositoryProvider)
          .getByFilterString(filter, {
            'sort_by': ['due_date'],
            'order_by': ['asc'],
          });

      if (!mounted) return;
      if (response.isSuccessful) {
        _tasks = response.toSuccess().body;
      } else if (response.isError) {
        _error = response.toError().error;
      } else if (response.isException) {
        _error = response.toException().message;
      }
    } catch (e) {
      if (mounted) _error = e;
    }
  }

  Future<void> _loadProjects() async {
    try {
      final response = await ref.read(projectRepositoryProvider).getAll();
      if (!mounted) return;
      if (response.isSuccessful) {
        _projectMap = {for (final p in response.toSuccess().body) p.id: p};
      }
    } catch (_) {}
  }

  Future<void> _loadGoogleEvents() async {
    final month = _currentMonth();
    if (month == _lastFetchedMonth) return;

    final ds = GoogleCalendarDataSource(ref.read(clientProviderProvider));
    try {
      final response = await ds.getUserEvents(month);
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
        _googleEventMap = map;
        _lastFetchedMonth = month;
      }
    } catch (_) {
      // Silently ignore — Google Calendar may not be enabled or linked
    }
  }

  Map<DateTime, List<Task>> _buildEventMap() {
    final map = <DateTime, List<Task>>{};
    for (final task in _tasks) {
      final due = task.dueDate;
      if (due == null) continue;
      final key = _normalise(due);
      (map[key] ??= []).add(task);
    }
    return map;
  }

  List<Task> _tasksForDay(Map<DateTime, List<Task>> map, DateTime day) {
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

  Future<void> _onMonthChanged(DateTime focusedDay) async {
    _focusedDay = focusedDay;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingWidget();
    if (_error != null) {
      return VikunjaErrorWidget(
        error: _error!,
        onRetry: _loadData,
      );
    }

    final eventMap = _buildEventMap();
    final selectedTasks =
        _selectedDay != null ? _tasksForDay(eventMap, _selectedDay!) : <Task>[];
    final selectedGoogleEvents =
        _selectedDay != null ? _googleEventsForDay(_selectedDay!) : <GoogleCalendarEvent>[];

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
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
                ..._tasksForDay(eventMap, day),
                ..._googleEventsForDay(day),
              ],
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) => _onMonthChanged(focusedDay),
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
              child: Text(
                _formatDate(context, _selectedDay!),
                style: Theme.of(context).textTheme.titleSmall,
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
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final task = selectedTasks[index];
                      final project = _projectMap[task.projectId];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AllProjectsTaskTile(task: task, project: project),
                          if (index < selectedTasks.length - 1 ||
                              selectedGoogleEvents.isNotEmpty)
                            const Divider(height: 1),
                        ],
                      );
                    },
                    childCount: selectedTasks.length,
                  ),
                ),
              if (selectedGoogleEvents.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
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
                    },
                    childCount: selectedGoogleEvents.length,
                  ),
                ),
            ],
            const SliverToBoxAdapter(
              child: Divider(height: 8, thickness: 4),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
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

class _AllProjectsTaskTile extends StatelessWidget {
  final Task task;
  final Project? project;

  const _AllProjectsTaskTile({required this.task, this.project});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        task.done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: task.done
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: task.done
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: project != null
          ? Text(
              project!.title,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
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
      leading: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFF4285F4),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text(
            'G',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
      title: Text(
        event.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: event.allDay
          ? null
          : Text(
              formatTime(event),
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }
}
