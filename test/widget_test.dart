import 'package:flutter_test/flutter_test.dart';
import 'package:qf_tv/models/models.dart';

void main() {
  test('DisplayTemplate parses split layout from json', () {
    final template = DisplayTemplate.fromJson({
      'id': 'dtpl_test',
      'name': 'Test',
      'version': 1,
      'layout': {'type': 'split_vertical'},
      'zones': [],
    });

    expect(template.layout.type, 'split_vertical');
    expect(template.id, 'dtpl_test');
  });
}
