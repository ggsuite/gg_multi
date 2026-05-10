// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gg_multi/src/backend/pub_dev_checker.dart';
import 'package:test/test.dart';

void main() {
  group('PubDevChecker', () {
    group('getPackagePublishInfo', () {
      test('waits for pub.dev when package already exists on pub.dev',
          () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"name": "repo", "versions": []}',
              200,
            ),
          ),
        );

        final info = await checker.getPackagePublishInfo(
          packageName: 'repo',
        );

        expect(info.packageName, 'repo');
        expect(info.waitsForPubDev, isTrue);
      });

      test('does not wait when package does not exist on pub.dev', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response('Not found', 404),
          ),
        );

        final info = await checker.getPackagePublishInfo(
          packageName: 'repo_none',
        );

        expect(info.packageName, 'repo_none');
        expect(info.waitsForPubDev, isFalse);
      });
    });

    group('packageExistsOnPubDev', () {
      test('throws on unexpected non-200 response', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response('Forbidden', 403),
          ),
        );

        await expectLater(
          checker.packageExistsOnPubDev(packageName: 'repo_forbidden'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to query pub.dev for repo_forbidden '),
            ),
          ),
        );
      });

      test('returns false on socket exception', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        );

        final exists = await checker.packageExistsOnPubDev(
          packageName: 'offline_package',
        );

        expect(exists, isFalse);
      });

      test('returns false on client exception', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => throw http.ClientException('client error'),
          ),
        );

        final exists = await checker.packageExistsOnPubDev(
          packageName: 'client_error_package',
        );

        expect(exists, isFalse);
      });
    });

    group('isVersionAvailable', () {
      test('returns true when version exists', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"versions": [{"pubspec": {"version": "1.2.3"}}]}',
              200,
            ),
          ),
        );

        final result = await checker.isVersionAvailable(
          packageName: 'a',
          version: '1.2.3',
        );

        expect(result, isTrue);
      });

      test('returns false when version does not exist', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"versions": [{"pubspec": {"version": "1.0.0"}}]}',
              200,
            ),
          ),
        );

        final result = await checker.isVersionAvailable(
          packageName: 'a',
          version: '1.2.3',
        );

        expect(result, isFalse);
      });

      test('returns false on 404', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response('Not found', 404),
          ),
        );

        final result = await checker.isVersionAvailable(
          packageName: 'a',
          version: '1.2.3',
        );

        expect(result, isFalse);
      });

      test('returns false on server error for retryable polling', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response('Server error', 500),
          ),
        );

        final result = await checker.isVersionAvailable(
          packageName: 'a',
          version: '1.2.3',
        );

        expect(result, isFalse);
      });

      test('throws on unexpected non-200 response', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response('Forbidden', 403),
          ),
        );

        await expectLater(
          checker.isVersionAvailable(
            packageName: 'repo_forbidden',
            version: '1.2.3',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to query pub.dev for repo_forbidden '),
            ),
          ),
        );
      });

      test('throws when response body is not a map', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '[1, 2, 3]',
              200,
            ),
          ),
        );

        await expectLater(
          checker.isVersionAvailable(
            packageName: 'broken_payload',
            version: '1.2.3',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Invalid pub.dev response for broken_payload.'),
            ),
          ),
        );
      });

      test('throws when versions payload is not a list', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"versions": {"bad": true}}',
              200,
            ),
          ),
        );

        await expectLater(
          checker.isVersionAvailable(
            packageName: 'broken_versions',
            version: '1.2.3',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains(
                'Invalid pub.dev versions payload for broken_versions.',
              ),
            ),
          ),
        );
      });
    });

    group('waitUntilVersionAvailable', () {
      test('waits until version appears', () async {
        var calls = 0;
        final checker = PubDevChecker(
          httpClient: MockClient((_) async {
            calls++;
            if (calls < 3) {
              return http.Response(
                '{"versions": [{"pubspec": {"version": "1.0.0"}}]}',
                200,
              );
            }
            return http.Response(
              '{"versions": [{"pubspec": {"version": "1.2.3"}}]}',
              200,
            );
          }),
          delay: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          timeout: const Duration(seconds: 1),
        );

        await checker.waitUntilVersionAvailable(
          packageName: 'a',
          version: '1.2.3',
          ggLog: (_) {},
        );
      });

      test('throws on timeout', () async {
        final checker = PubDevChecker(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"versions": []}',
              200,
            ),
          ),
          delay: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          timeout: Duration.zero,
        );

        await expectLater(
          () => checker.waitUntilVersionAvailable(
            packageName: 'a',
            version: '1.2.3',
            ggLog: (_) {},
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Timed out waiting for a 1.2.3'),
            ),
          ),
        );
      });
    });

    group('Integration', () {
      test('queries pub.dev package availability', () async {
        final checker = PubDevChecker();

        final isOnPubDev = await checker.packageExistsOnPubDev(
          packageName: 'gg_multi',
        );
        expect(isOnPubDev, isTrue);

        final isOnPubDev2 = await checker.packageExistsOnPubDev(
          packageName: 'ggggg',
        );
        expect(isOnPubDev2, isFalse);
      });
    });
  });
}
