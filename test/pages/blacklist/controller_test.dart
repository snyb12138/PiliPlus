import 'package:PiliPlus/pages/blacklist/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBlackMids', () {
    test('accepts integer and decimal string UIDs and removes duplicates', () {
      expect(
        parseBlackMids([123, ' 456 ', 123]),
        {123, 456},
      );
    });

    test('rejects non-positive and malformed UIDs with their position', () {
      expect(
        () => parseBlackMids([123, 0]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('第 2 项'),
          ),
        ),
      );
      expect(
        () => parseBlackMids(['not-a-uid']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
