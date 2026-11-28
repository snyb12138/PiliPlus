import 'package:flutter_test/flutter_test.dart';

import 'reply_number_scan_cases.dart' as cases;

void main() {
  test(
    'assembles comment numbers and scans reply and folded pages',
    cases.main,
  );
}
