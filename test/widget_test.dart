// Scan & Score App Widget Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_score/models/participant.dart';

void main() {
  group('Participant Model Tests', () {
    test('fromCsvRow parses correctly', () {
      final row = ['张三', '001', 'A组', 'avatar_001.jpg', '李领队'];
      final participant = Participant.fromCsvRow(row, rowIndex: 0);

      expect(participant.name, '张三');
      expect(participant.memberCode, '001');
      expect(participant.group, 'A组');
      expect(participant.avatarPath, 'avatar_001.jpg');
      expect(participant.leaderName, '李领队');
      expect(participant.workCode, null);
      expect(participant.checkStatus, 0);
    });

    test('toCsvRow exports correctly', () {
      final participant = Participant(
        id: 0,
        name: '张三',
        memberCode: '001',
        group: 'A组',
        avatarPath: 'avatar_001.jpg',
        leaderName: '李领队',
        workCode: 'W001',
        checkStatus: 1,
        score: 85.5,
        evidenceImg: '/path/to/photo.jpg',
      );

      final row = participant.toCsvRow();

      expect(row[0], '张三');
      expect(row[1], '001');
      expect(row[2], 'A组');
      expect(row[3], 'avatar_001.jpg');
      expect(row[4], '李领队');
      expect(row[5], 'W001');
      expect(row[6], 1);
      expect(row[7], '85.5');
      expect(row[8], '/path/to/photo.jpg');
    });

    test('copyWith creates new instance with updated values', () {
      final original = Participant(
        id: 0,
        name: '张三',
        memberCode: '001',
        group: 'A组',
      );

      final updated = original.copyWith(workCode: 'W001', checkStatus: 1);

      expect(updated.name, '张三');
      expect(updated.workCode, 'W001');
      expect(updated.checkStatus, 1);
      expect(original.workCode, null);
      expect(original.checkStatus, 0);
    });
  });
}
