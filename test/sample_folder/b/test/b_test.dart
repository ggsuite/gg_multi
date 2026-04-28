import 'package:b/src/b.dart';
import 'package:test/test.dart';

void main() {
  group('TestGroup', () {
    test('TestCase', () {
      expect(greetFromB(), 'hello from b');
    });
  });
}
