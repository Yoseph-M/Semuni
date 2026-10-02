/// A stop on a route, as identified by the backend.
///
/// [id] is the authoritative `RouteStop` UUID: it is what fare quotes and trip
/// creation accept. [name] is display text only and is never an identifier.
class RouteStop {
  const RouteStop({
    required this.id,
    required this.name,
    required this.sequence,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;

  /// 1-based position along the route; the backend rejects journeys whose
  /// origin is not before the destination.
  final int sequence;

  final double? latitude;
  final double? longitude;

  @override
  String toString() => 'RouteStop($sequence. $name, id: $id)';
}

/// Passenger-facing taxi route for discovery and booking.
///
/// Represents a public minibus / taxi route a passenger can search for,
/// browse, and use to start a ride booking.
///
/// This is the passenger-side model. Driver-side route assignment uses
/// [DriverRoute] which carries driver-operational fields.
class PassengerRoute {
  const PassengerRoute({
    required this.id,
    required this.name,
    required this.startStation,
    required this.endStation,
    required this.startLabel,
    required this.endLabel,
    required this.fare,
    required this.isAvailable,
    this.routeCode,
    this.estimatedDuration,
    this.intermediateStops = const [],
    this.operatingHours,
    this.distanceKm,
    this.instructions,
    this.stops = const [],
  });

  final String id;

  /// Human-readable route name, e.g. "Bole → Piazza".
  final String name;

  /// Internal key for the starting station (used for filtering).
  final String startStation;

  /// Internal key for the ending station (used for filtering).
  final String endStation;

  /// Display label for the start station.
  final String startLabel;

  /// Display label for the end station.
  final String endLabel;

  /// Standard passenger fare in ETB.
  final double fare;

  /// Whether taxis are currently running on this route.
  final bool isAvailable;

  /// Official route code (e.g. "ET-RT-01").
  final String? routeCode;

  /// Estimated travel duration (e.g. "30–40 min").
  final String? estimatedDuration;

  /// Intermediate stops/stations along this route.
  final List<String> intermediateStops;

  /// Daily operating hours (e.g. "06:00 AM – 10:00 PM").
  final String? operatingHours;

  /// Approximate route distance in kilometres.
  final double? distanceKm;

  /// Short passenger-facing boarding/travel instructions.
  final String? instructions;

  /// Ordered stops with backend UUIDs, when the route came from the API.
  ///
  /// The fare and trip flows need these identifiers; names alone are display
  /// only. Empty for routes that were assembled without stop data.
  final List<RouteStop> stops;

  @override
  String toString() =>
      'PassengerRoute(id: $id, name: $name, fare: $fare, available: $isAvailable)';
}

/// A taxi station / stop on the SMUNI network.
///
/// Used by the map screen to represent individual locations
/// passengers can tap or search for.
class TaxiStation {
  const TaxiStation({
    required this.id,
    required this.name,
    required this.label,
    required this.mapX,
    required this.mapY,
    this.isHub = false,
  });

  /// Unique station identifier (matches [PassengerRoute.startStation] /
  /// [PassengerRoute.endStation] keys).
  final String id;

  /// Short name used in search and filtering (e.g. "Bole").
  final String name;

  /// Display label shown on the map marker.
  final String label;

  /// Relative X position on the mock map canvas (0.0 – 1.0).
  final double mapX;

  /// Relative Y position on the mock map canvas (0.0 – 1.0).
  final double mapY;

  /// Whether this station is a major transport hub.
  final bool isHub;

  @override
  String toString() => 'TaxiStation(id: $id, name: $name)';
}
