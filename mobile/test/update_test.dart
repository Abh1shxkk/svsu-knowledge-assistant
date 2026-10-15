import 'package:flutter_test/flutter_test.dart';
import 'package:svsu_assistant/update.dart';

void main() {
  test('a release is offered only when its version is higher', () {
    expect(isNewer('1.1.0', '1.0.0'), isTrue);
    expect(isNewer('1.10.0', '1.9.2'), isTrue); // number by number, not as text
    expect(isNewer('2.0.0', '1.99.99'), isTrue);
    expect(isNewer('1.0.0', '1.0.0'), isFalse);
    expect(isNewer('1.0.0', '1.0.1'), isFalse);
    expect(isNewer('1.0', '1.0.0'), isFalse);
  });
}
