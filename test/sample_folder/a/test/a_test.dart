import 'package:a/src/a.dart';
import 'package:test/test.dart';

void main() {
  group('TestGroup', () {
    test('TestCase', () {
      expect(greetFromA('Test'), equals('a -> Test'));
    });
  });
}
