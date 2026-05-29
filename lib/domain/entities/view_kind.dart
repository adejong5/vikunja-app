enum ViewKind {
  list,
  gantt,
  table,
  kanban,
  calendar;

  static ViewKind fromString(String viewKind) {
    switch (viewKind) {
      case "list":
        return list;
      case "gantt":
        return gantt;
      case "table":
        return table;
      case "kanban":
        return kanban;
      case "calendar":
        return calendar;
      default:
        throw Error();
    }
  }
}
