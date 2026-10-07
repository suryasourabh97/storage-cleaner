import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage_cleaner/platform/windows/windows_fs.dart';
import 'package:storage_cleaner/ui/format.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 bytes');
    expect(formatBytes(1), '1 byte');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(500 * 1024 * 1024), '500 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024 + 800 * 1024 * 1024), '3.8 GB');
  });

  test('plural', () {
    expect(plural(1, 'file'), '1 file');
    expect(plural(3, 'file'), '3 files');
  });

  test('batch summary lists skip reasons', () {
    final r = BatchResult(const [
      OpDone('a'),
      OpDone('b'),
      OpSkipped('c', SkipReason.inUse),
      OpSkipped('d', SkipReason.inUse),
      OpSkipped('e', SkipReason.changedSinceScan),
    ]);
    expect(
      summarizeBatch(r, 'moved to trash'),
      '2 files moved to trash. 3 skipped: 2 open in another app, '
      '1 changed since the scan.',
    );
  });

  test('FILETIME conversion', () {
    // 1970-01-01T00:00:00Z as a FILETIME.
    const ticks = 116444736000000000;
    final t = fileTimeToDateTime(ticks >> 32, ticks & 0xFFFFFFFF);
    expect(t, DateTime.utc(1970));
  });

  test('reparse classification: junction yes, OneDrive placeholder no', () {
    const reparse = 0x400;
    const mountPointTag = 0xA0000003; // IO_REPARSE_TAG_MOUNT_POINT
    const symlinkTag = 0xA000000C; // IO_REPARSE_TAG_SYMLINK
    const cloudTag = 0x9001101A; // IO_REPARSE_TAG_CLOUD_1
    expect(attrsFrom(reparse | 0x10, mountPointTag).isLink, isTrue);
    expect(attrsFrom(reparse, symlinkTag).isLink, isTrue);
    expect(attrsFrom(reparse, cloudTag).isLink, isFalse);
    expect(attrsFrom(reparse | 0x400000, cloudTag).onlineOnly, isTrue);
    expect(attrsFrom(0x20, 0).isLink, isFalse);
  });
}
