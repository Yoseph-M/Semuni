/// Passenger model.
///
/// Represents the passenger user in the semuni system.
/// This is a pure data class — no UI logic here.
class Passenger {
  const Passenger({
    required this.id,
    required this.name,
    required this.username,
    required this.phone,
    required this.walletBalance,
  });

  final String id;
  final String name;
  final String username;
  final String phone;
  final double walletBalance;

  /// First name derived from [name].
  String get firstName => name.split(' ').first;

  Passenger copyWith({
    String? id,
    String? name,
    String? username,
    String? phone,
    double? walletBalance,
  }) {
    return Passenger(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      walletBalance: walletBalance ?? this.walletBalance,
    );
  }

  @override
  String toString() =>
      'Passenger(id: $id, name: $name, walletBalance: $walletBalance)';
}
