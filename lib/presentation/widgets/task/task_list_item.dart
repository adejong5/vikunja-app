import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vikunja_app/core/di/network_provider.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/presentation/widgets/due_date_card.dart';
import 'package:vikunja_app/presentation/widgets/project/kanban/priority_batch.dart';
import 'package:vikunja_app/presentation/widgets/task/task_actions.dart';

class TaskListItem extends ConsumerStatefulWidget {
  final Task task;
  final Function onTap;
  final Function onEdit;
  final Function(bool value) onCheckedChanged;

  const TaskListItem({
    super.key,
    required this.task,
    required this.onTap,
    required this.onEdit,
    required this.onCheckedChanged,
  });

  @override
  TaskListItemState createState() => TaskListItemState();
}

class TaskListItemState extends ConsumerState<TaskListItem> {
  TaskListItemState();

  Map<String, String>? _authHeaders;

  @override
  void initState() {
    super.initState();
    ref.read(clientProviderProvider).getHeaders().then((h) {
      if (mounted) setState(() => _authHeaders = h);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.loose,
      children: [
        ListTile(
          onTap: () {
            widget.onTap();
          },
          contentPadding: const EdgeInsetsDirectional.only(
            start: 16.0,
            end: 8.0,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.task.assignees.isNotEmpty && _authHeaders != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundImage: NetworkImage(
                      widget.task.assignees.first.avatarUrl(
                        ref.read(clientProviderProvider).apiBase,
                      ),
                      headers: _authHeaders,
                    ),
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
          subtitle: _buildTaskSubtitle(widget.task, context),
          leading: Checkbox(
            value: widget.task.done,
            onChanged: (bool? newValue) {
              if (newValue != null) {
                widget.onCheckedChanged(newValue);
              }
            },
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TaskActions(
                task: widget.task,
                onEdit: () => widget.onEdit(),
                variant: TaskActionsVariant.menu,
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: 4.0,
          child: Container(color: widget.task.color),
        ),
      ],
    );
  }

  Widget? _buildTaskSubtitle(Task task, BuildContext context) {
    List<Widget> texts = [];

    if (task.hasDueDate) {
      texts.add(
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: DueDateCard(task.dueDate!),
        ),
      );
    }
    if (task.priority != null && task.priority != 0) {
      texts.add(PriorityBatch(task.priority!));
    }

    var project = task.project;

    if (texts.isEmpty) {
      if (project != null) {
        return Text(project.title);
      }

      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project != null)
            Text(project.title, style: Theme.of(context).textTheme.bodyMedium),
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(children: texts),
          ),
        ],
      ),
    );
  }
}
