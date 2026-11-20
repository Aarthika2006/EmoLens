import 'package:test/test.dart';
import 'package:emolens/core/utils/validators.dart';

void main() {
  group('Validators.validateIPv4', () {
    test('valid IPs pass', () {
      expect(Validators.validateIPv4('192.168.1.100'), isNull);
      expect(Validators.validateIPv4('10.0.0.1'), isNull);
      expect(Validators.validateIPv4('255.255.255.0'), isNull);
      expect(Validators.validateIPv4('0.0.0.0'), isNull);
    });

    test('null/empty input fails', () {
      expect(Validators.validateIPv4(null), isNotNull);
      expect(Validators.validateIPv4(''), isNotNull);
      expect(Validators.validateIPv4('   '), isNotNull);
    });

    test('wrong octet count fails', () {
      expect(Validators.validateIPv4('192.168.1'), isNotNull);
      expect(Validators.validateIPv4('192.168.1.1.1'), isNotNull);
      expect(Validators.validateIPv4('192.168'), isNotNull);
    });

    test('out-of-range octets fail', () {
      expect(Validators.validateIPv4('256.0.0.1'), isNotNull);
      expect(Validators.validateIPv4('192.168.-1.1'), isNotNull);
      expect(Validators.validateIPv4('192.168.1.999'), isNotNull);
    });

    test('non-numeric octets fail', () {
      expect(Validators.validateIPv4('a.b.c.d'), isNotNull);
      expect(Validators.validateIPv4('192.168.1.x'), isNotNull);
    });

    test('leading zeros rejected', () {
      expect(Validators.validateIPv4('192.168.01.1'), isNotNull);
      expect(Validators.validateIPv4('010.0.0.1'), isNotNull);
    });
  });

  group('Validators.validatePort', () {
    test('valid ports pass', () {
      expect(Validators.validatePort('80'), isNull);
      expect(Validators.validatePort('81'), isNull);
      expect(Validators.validatePort('8080'), isNull);
      expect(Validators.validatePort('65535'), isNull);
      expect(Validators.validatePort('1'), isNull);
    });

    test('null/empty fails', () {
      expect(Validators.validatePort(null), isNotNull);
      expect(Validators.validatePort(''), isNotNull);
    });

    test('out-of-range ports fail', () {
      expect(Validators.validatePort('0'), isNotNull);
      expect(Validators.validatePort('65536'), isNotNull);
      expect(Validators.validatePort('-1'), isNotNull);
    });

    test('non-numeric fails', () {
      expect(Validators.validatePort('abc'), isNotNull);
      expect(Validators.validatePort('8O'), isNotNull); // letter O not zero
    });
  });
}

