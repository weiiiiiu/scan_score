// Scan & Score App Widget Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_score/models/participant.dart';

void main() {
  group('Participant Model Tests', () {
    test('fromCsvRow parses correctly', () {
      final row = ['001', '张三', 'A组', '编程', '红星队', '李辅导员'];
      final participant = Participant.fromCsvRow(row, rowIndex: 0);

      expect(participant.memberCode, '001');
      expect(participant.name, '张三');
      expect(participant.group, 'A组');
      expect(participant.project, '编程');
      expect(participant.teamName, '红星队');
      expect(participant.instructorName, '李辅导员');
      expect(participant.workCode, null);
      expect(participant.checkStatus, 0);
    });

    test('toCsvRow exports correctly', () {
      final participant = Participant(
        id: 0,
        name: '张三',
        memberCode: '001',
        group: 'A组',
        project: '编程',
        teamName: '红星队',
        instructorName: '李辅导员',
        workCode: 'W001',
        checkStatus: 1,
        score: 85.5,
        evidenceImg: '/path/to/photo.jpg',
      );

      final row = participant.toCsvRow();

      expect(row[0], '001');
      expect(row[1], '张三');
      expect(row[2], 'A组');
      expect(row[3], '编程');
      expect(row[4], '红星队');
      expect(row[5], '李辅导员');
      expect(row[6], 'W001');
      expect(row[7], 1);
      expect(row[8], '85.5');
      expect(row[9], '/path/to/photo.jpg');
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
