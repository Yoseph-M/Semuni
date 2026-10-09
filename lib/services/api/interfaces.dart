import '../../models/app_notification.dart';
import '../../models/available_driver.dart';
import '../../models/driver_activity.dart';
import '../../models/driver_route.dart';
import '../../models/driver_transaction.dart';
import '../../models/driver_withdrawal.dart';
import '../../models/fare_quote.dart';
import '../../models/passenger_route.dart';
import '../../models/passenger_wallet_transaction.dart';
import '../../models/top_up_intent.dart';
import '../../models/trip.dart';

abstract interface class DriverDiscoveryService {
  Future<List<AvailableDriver>> getAvailableDrivers();
  Future<AvailableDriver?> findByLicense(String licenseNumber);
}

abstract interface class PassengerRouteService {
  /// Retrieves all stations on the semuni taxi network.
  Future<List<TaxiStation>> getStations();

  /// Retrieves all available passenger routes.
  Future<List<PassengerRoute>> getAllRoutes();

  /// Searches routes where the destination matches [query].
  ///
  /// [query] is matched case-insensitively against station names and labels.
  Future<List<PassengerRoute>> searchByDestination(String query);

  /// Returns all routes that serve [stationId] as a destination.
  Future<List<PassengerRoute>> getRoutesToStation(String stationId);

  /// Searches routes matching both starting and ending points.
  Future<List<PassengerRoute>> searchRoutes({
    required String fromQuery,
    required String toQuery,
  });

  /// Asks the backend for the official fare of a specific segment.
  ///
  /// This is the only source of a payable price: the client must never derive
  /// one from [PassengerRoute.fare] or from its own arithmetic.
  Future<FareQuote> quoteFare({
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    String? vehicleType,
  });
}

abstract interface class DriverDashboardService {
  /// Fetches daily activity metrics for the authenticated driver.
  Future<DriverActivity> getTodayActivity();

  /// Fetches the recent transactions for the authenticated driver.
  Future<List<DriverTransaction>> getRecentTransactions({int limit = 5});

  /// Requests a withdrawal from the driver's wallet.
  ///
  /// There is no generic "method" string in the financial contract: the
  /// destination type, destination and an idempotency key are explicit, and
  /// the backend re-checks the driver's balance and status itself.
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  });
}

abstract interface class TripService {
  /// Fetches the recent trips taken by the passenger.
  Future<List<Trip>> getRecentTrips({int limit = 5});

  /// Loads one trip by its backend id.
  Future<Trip> getTrip(String tripId);

  /// Creates a trip for a journey the passenger is actually taking.
  ///
  /// The backend prices it; [driverId] is the driver's user id.
  Future<Trip> createTrip({
    required String driverId,
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    required String origin,
    required String destination,
    String? vehicleId,
    String? vehicleType,
  });

  /// Records a completed taxi journey (mock-era; no backend equivalent).
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  });

  /// Books a new ride request for the passenger (mock-era; no backend equivalent).
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  });
}

abstract class PassengerWalletService {
  /// Current wallet balance in ETB, read from the backend.
  Future<double> getBalance(String passengerId);

  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  );

  /// Creates a top-up intent. The balance does not change here.
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  });

  /// Confirms the top-up; the backend verifies the provider and credits once.
  Future<TopUpConfirmation> confirmTopUp(String intentId);

  /// Settles a top-up with an external receipt (links.et) after paying outside
  /// the app — a bank transfer, a Telebirr payment made elsewhere, or a receipt
  /// screenshot.
  ///
  /// The backend performs the verification: it resolves the receipt with
  /// links.et, checks the amount, currency, provider reference and owner, and
  /// credits the wallet at most once per receipt. A receipt that cannot be
  /// verified upstream settles nothing, so passing an image here is a request
  /// for verification, never a claim of payment.
  Future<TopUpConfirmation> verifyReceipt({
    required String intentId,
    String? reference,
    String? url,
    String? imageBase64,
  });

  /// Mock-era local credit. Production throws — the wallet is backend-owned.
  Future<PassengerWalletTransaction> topUp(String passengerId, double amount);

  /// Mock-era local debit. Production throws — payments go through `/payments/trip`.
  Future<PassengerWalletTransaction> payTaxiFare(
    String passengerId, {
    required double amount,
    required String description,
    String? referenceId,
  });
}

abstract interface class DriverRouteService {
  /// Retrieves all routes assigned to the authenticated driver.
  Future<List<DriverRoute>> getAssignedRoutes();

  /// Retrieves a specific route by its identifier.
  Future<DriverRoute?> getRouteById(String id);
}

abstract interface class NotificationService {
  /// Whether this service can actually answer notification queries.
  ///
  /// The backend currently has no notification *read* endpoints — it owns an
  /// outbox that pushes messages, not a history a client can list. A service
  /// that cannot answer therefore says so, instead of returning an empty list
  /// that a screen would show as "you have no notifications".
  bool get isSupported;

  /// Fetches all notifications for the current passenger.
  Future<List<AppNotification>> getNotifications();

  /// Marks a single notification as read by [id].
  ///
  /// Returns the updated [AppNotification].
  Future<AppNotification> markAsRead(String id);

  /// Marks all notifications as read.
  Future<void> markAllAsRead();
}
