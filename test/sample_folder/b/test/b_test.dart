// Use a relative import so this fixture test also loads from gg_multi's own
// `dart test` run (where `package:b` is not on the resolution path). It still
// resolves correctly when the fixture is run in its own package context.
import '../lib/src/b.dart';

import 'package:test/test.dart';

void main() {
  group('TestGroup', () {
    test('TestCase', () {
      expect(greetFromB(), 'hello from b');
    });
  });
}
