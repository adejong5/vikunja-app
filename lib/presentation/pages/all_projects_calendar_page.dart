import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).calendarTab),
      ),
      body: RefreshIndicator(
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
      leading: SvgPicture.string(
        _kGoogleLogoSvg,
        width: 24,
        height: 24,
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

const _kGoogleLogoSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
  <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
  <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
  <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
</svg>
''';
