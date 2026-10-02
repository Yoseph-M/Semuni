import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/core/network/api_exception.dart';
import 'package:smuni/services/api/api_passenger_route_service.dart';

/// Contract tests for route discovery: backend UUIDs, minor-unit fares and
/// PostgreSQL's string-encoded decimals.
void main() {
  const baseUrl = 'http://backend.test';

  ApiClient clientWith(MockClient mock) => ApiClient(
    httpClient: mock,
    session: AuthSession(tokenStore: InMemoryTokenStore()),
    baseUrl: baseUrl,
  );

  // `http.Response` encodes its body as Latin-1 unless the content type says
  // otherwise; real backend responses are UTF-8, and route names contain
  // characters like '–' that are not Latin-1.
  http.Response envelope(Object? data, [int status = 200]) => http.Response(
    jsonEncode({'data': data, 'meta': {}}),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  // A realistic payload: `latitude` arrives as a string (pg decimal), stops as
  // UUIDs, and the route carries human-readable names as well.
  final routeJson = <String, dynamic>{
    'id': 'route-uuid-1',
    'name': 'Bole – Piazza',
    'code': 'SAMPLE-01',
    'origin': 'Bole',
    'destination': 'Piazza',
    'status': 'ACTIVE',
    'stops': [
      {
        'id': 'stop-uuid-1',
        'name': 'Bole',
        'sequence': 1,
        'latitude': '8.994400',
        'longitude': '38.799400',
      },
      {
        'id': 'stop-uuid-2',
        'name': 'Meskel Square',
        'sequence': 2,
        'latitude': '9.010700',
        'longitude': '38.761200',
      },
      {
        'id': 'stop-uuid-3',
        'name': 'Piazza',
        'sequence': 3,
        'latitude': null,
        'longitude': null,
      },
    ],
  };

  Map<String, dynamic> quoteJson(int fareMinor) => {
    'fare': fareMinor,
    'currency': 'ETB',
    'routeId': 'route-uuid-1',
    'routeName': 'Bole – Piazza',
    'originStopId': 'stop-uuid-1',
    'originStopName': 'Bole',
    'destinationStopId': 'stop-uuid-3',
    'destinationStopName': 'Piazza',
    'tariffId': 'tariff-uuid',
    'tariffVersion': 'TARIFF-SAMPLE-V1',
    'tariffRuleId': 'rule-uuid',
  };

  test('parses routes with UUID stops and converts minor-unit fares to ETB',
      () async {
    final client = clientWith(
      MockClient((request) async {
        if (request.url.path == '/api/v1/routes') {
          return envelope([routeJson]);
        }
        if (request.url.path == '/api/v1/fares/calculate') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // Quoted for the full corridor, from stop ids — never from names.
          expect(body['routeId'], 'route-uuid-1');
          expect(body['originStopId'], 'stop-uuid-1');
          expect(body['destinationStopId'], 'stop-uuid-3');
          return envelope(quoteJson(8500));
        }
        fail('unexpected call ${request.url}');
      }),
    );

    final routes = await ApiPassengerRouteService(client: client).getAllRoutes();

    expect(routes, hasLength(1));
    final route = routes.single;
    expect(route.fare, 85.0, reason: '8500 santim is ETB 85.00');
    expect(route.isAvailable, isTrue);
    expect(
      route.stops.map((stop) => stop.id),
      ['stop-uuid-1', 'stop-uuid-2', 'stop-uuid-3'],
    );
    expect(route.startStation, 'stop-uuid-1');
    expect(route.endStation, 'stop-uuid-3');
    expect(route.stops.first.latitude, closeTo(8.9944, 0.0000001));
    expect(route.stops.last.latitude, isNull, reason: 'a missing coordinate is tolerated');
    expect(route.intermediateStops, ['Meskel Square']);
  });

  test('a route the fare engine cannot price is unavailable, not free',
      () async {
    final client = clientWith(
      MockClient((request) async {
        if (request.url.path == '/api/v1/routes') return envelope([routeJson]);
        if (request.url.path == '/api/v1/fares/calculate') {
          return http.Response(
            jsonEncode({
              'code': ApiErrorCodes.tariffRuleNotFound,
              'message': 'No tariff rule',
            }),
            404,
          );
        }
        fail('unexpected call ${request.url}');
      }),
    );

    final route =
        (await ApiPassengerRouteService(client: client).getAllRoutes()).single;

    expect(route.fare, 0);
    expect(route.isAvailable, isFalse);
  });

  test('an inactive route is unavailable even with a published fare',
      () async {
    final inactive = Map<String, dynamic>.from(routeJson)
      ..['status'] = 'INACTIVE';
    final client = clientWith(
      MockClient((request) async {
        if (request.url.path == '/api/v1/routes') return envelope([inactive]);
        if (request.url.path == '/api/v1/fares/calculate') {
          return envelope(quoteJson(7000));
        }
        fail('unexpected call ${request.url}');
      }),
    );

    final route =
        (await ApiPassengerRouteService(client: client).getAllRoutes()).single;

    expect(route.fare, 70.0);
    expect(route.isAvailable, isFalse);
  });

  test('quoteFare sends the chosen segment and keeps backend error codes',
      () async {
    final client = clientWith(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['originStopId'], 'stop-uuid-2');
        expect(body['destinationStopId'], 'stop-uuid-3');
        return http.Response(
          jsonEncode({
            'code': ApiErrorCodes.stopOrderInvalid,
            'message': 'Destination stop must occur after origin stop',
          }),
          400,
        );
      }),
    );

    await expectLater(
      ApiPassengerRouteService(client: client).quoteFare(
        routeId: 'route-uuid-1',
        originStopId: 'stop-uuid-2',
        destinationStopId: 'stop-uuid-3',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCodes.stopOrderInvalid,
        ),
      ),
    );
  });
}
