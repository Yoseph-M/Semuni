/// Driver model.
///
/// Represents the driver user in the semuni system.
/// This is a pure data class — no UI logic here.
class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.username,
    required this.phone,
    required this.accountBalance,
    required this.todayEarnings,
    required this.licenseNumber,
    required this.vehiclePlate,
  });

  final String id;
  final String name;
  final String username;
  final String phone;
  final double accountBalance;
  final double todayEarnings;
  final String licenseNumber;
  final String vehiclePlate;

  /// First name derived from [name].
  String get firstName => name.split(' ').first;

  Driver copyWith({
    String? id,
    String? name,
    String? username,
    String? phone,
    double? accountBalance,
    double? todayEarnings,
    String? licenseNumber,
    String? vehiclePlate,
  }) {
    return Driver(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      accountBalance: accountBalance ?? this.accountBalance,
      todayEarnings: todayEarnings ?? this.todayEarnings,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
    );
  }

  @override
  String toString() =>
      'Driver(id: $id, name: $name, accountBalance: $accountBalance)';
}
