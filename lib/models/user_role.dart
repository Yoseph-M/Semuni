/// User role in the semuni application.
///
/// Determines the authentication context and the dashboard destination.
enum UserRole {
  passenger('Passenger'),
  driver('Driver');

  const UserRole(this.label);

  final String label;

  bool get isPassenger => this == UserRole.passenger;
  bool get isDriver => this == UserRole.driver;
}
