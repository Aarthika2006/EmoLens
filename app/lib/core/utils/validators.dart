/// Input validation utilities.
class Validators {
  Validators._();

  /// Validates an IPv4 address string.
  /// Returns null if valid, error message if invalid.
  static String? validateIPv4(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'IP address is required';
    }

    final trimmed = value.trim();
    final parts = trimmed.split('.');
    if (parts.length != 4) {
      return 'Invalid IPv4 format (expected x.x.x.x)';
    }

    for (final part in parts) {
      if (part.isEmpty) return 'Invalid IPv4 format';
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) {
        return 'Each octet must be 0-255';
      }
      // Reject leading zeros (e.g., 01, 001)
      if (part.length > 1 && part.startsWith('0')) {
        return 'Octets must not have leading zeros';
      }
    }

    return null;
  }

  /// Validates a port number.
  /// Returns null if valid, error message if invalid.
  static String? validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }
    final n = int.tryParse(value.trim());
    if (n == null) return 'Port must be a number';
    if (n < 1 || n > 65535) return 'Port must be 1-65535';
    return null;
  }

  /// Returns true if the string is a valid IPv4 address.
  static bool isValidIPv4(String value) => validateIPv4(value) == null;

  /// Returns true if the string is a valid port.
  static bool isValidPort(String value) => validatePort(value) == null;
}
