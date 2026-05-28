import 'package:vikunja_app/core/network/remote_data_source.dart';
import 'package:vikunja_app/core/network/response.dart';
import 'package:vikunja_app/domain/entities/google_calendar_event.dart';

class GoogleCalendarDataSource extends RemoteDataSource {
  GoogleCalendarDataSource(super.client);

  Future<Response<List<GoogleCalendarEvent>>> getProjectEvents(
    int projectId,
    int viewId,
    String month,
  ) {
    return client.get(
      url: '/projects/$projectId/views/$viewId/google-events',
      mapper: (body) => convertList(
        body,
        (j) => GoogleCalendarEvent.fromJson(j as Map<String, dynamic>),
      ),
      queryParameters: {
        'month': [month],
      },
    );
  }

  Future<Response<List<GoogleCalendarEvent>>> getUserEvents(String month) {
    return client.get(
      url: '/user/settings/google/events',
      mapper: (body) => convertList(
        body,
        (j) => GoogleCalendarEvent.fromJson(j as Map<String, dynamic>),
      ),
      queryParameters: {
        'month': [month],
      },
    );
  }
}
