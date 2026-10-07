import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

void main() {
  test('paths compare case-insensitively', () {
    expect(samePath(r'C:\Users\Surya\Downloads', r'c:\users\surya\downloads\'),
        isTrue);
  });

  test('isWithin compares whole segments', () {
    expect(isWithin(r'C:\Users\a', r'C:\Users\a\file.txt'), isTrue);
    expect(isWithin(r'C:\Users\a', r'C:\Users\ab\file.txt'), isFalse);
    expect(isWithin(r'C:\Users\a', r'C:\Users\a'), isFalse);
    expect(isWithinOrEqual(r'C:\Users\a', r'C:\USERS\A'), isTrue);
    expect(isWithin(r'D:\', r'D:\Photos\x.jpg'), isTrue);
  });

  test('driveRoot', () {
    expect(driveRoot(r'C:\Users\a\b.txt'), r'C:\');
    expect(driveRoot(r'D:\'), r'D:\');
  });

  test('collision suffix goes before the extension', () {
    expect(withCollisionSuffix(r'C:\T\report.pdf', 1), r'C:\T\report (1).pdf');
    expect(withCollisionSuffix(r'C:\T\README', 2), r'C:\T\README (2)');
  });
}
