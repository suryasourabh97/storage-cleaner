import '../model/models.dart';
import '../model/path_key.dart';

/// Resolved Windows known folders for the current user. Any may be null if
/// it couldn't be resolved.
final class KnownFolders {
  const KnownFolders({
    required this.userProfile,
    this.downloads,
    this.documents,
    this.desktop,
    this.pictures,
    this.videos,
    this.music,
    this.oneDriveRoots = const [],
  });

  final String userProfile;
  final String? downloads;
  final String? documents;
  final String? desktop;
  final String? pictures;
  final String? videos;
  final String? music;
  final List<String> oneDriveRoots;
}

final class Categorization {
  const Categorization({
    required this.category,
    required this.isProtected,
    required this.cloudSynced,
  });

  final Category category;

  /// Shown but unselected by default (Pictures).
  final bool isProtected;

  /// Under a OneDrive root.
  final bool cloudSynced;
}

/// Assigns a category from folder and extension (spec §5.2).
final class Categorizer {
  const Categorizer(this.folders);

  final KnownFolders folders;

  static const installerExt = {
    '.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle', '.apk',
  };
  static const archiveExt = {
    '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.iso',
    '.img', '.cab', '.vhd', '.vhdx',
  };
  static const videoExt = {
    '.mp4', '.mkv', '.mov', '.avi', '.wmv', '.webm', '.m4v', '.flv', '.mpg',
    '.mpeg', '.3gp', '.mts', '.m2ts',
  };
  static const audioExt = {
    '.mp3', '.wav', '.flac', '.aac', '.m4a', '.ogg', '.wma', '.opus', '.aiff',
  };
  static const pictureExt = {
    '.jpg', '.jpeg', '.jpe', '.jfif', '.png', '.gif', '.bmp', '.tif', '.tiff',
    '.heic', '.heif', '.avif', '.webp', '.raw', '.cr2', '.cr3', '.nef',
    '.arw', '.dng', '.svg',
  };
  static const documentExt = {
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.odt', '.ods',
    '.odp', '.txt', '.rtf', '.csv', '.md', '.epub', '.one', '.vsdx',
  };

  /// Image file types compared for duplicates and similar photos.
  static const imageExt = {
    '.jpg', '.jpeg', '.jpe', '.jfif', '.png', '.webp', '.bmp', '.gif',
    '.tif', '.tiff', '.heic', '.heif', '.avif',
  };

  /// Images used for photo comparison: any file with an image extension,
  /// plus anything in the Pictures folder that isn't clearly another kind
  /// of file (video, audio, document, archive, installer).
  static bool isImagePath(String path, {String? picturesFolder}) {
    final ext = winPath.extension(path).toLowerCase();
    if (imageExt.contains(ext)) return true;
    if (picturesFolder == null || !isWithin(picturesFolder, path)) return false;
    return !videoExt.contains(ext) &&
        !audioExt.contains(ext) &&
        !documentExt.contains(ext) &&
        !archiveExt.contains(ext) &&
        !installerExt.contains(ext);
  }

  Categorization categorize(String path) {
    final ext = winPath.extension(path).toLowerCase();
    final inPictures =
        folders.pictures != null && isWithin(folders.pictures!, path);
    final cloud = folders.oneDriveRoots.any((r) => isWithin(r, path));

    final Category category;
    if (folders.downloads != null && isWithin(folders.downloads!, path)) {
      category = Category.downloads;
    } else if (installerExt.contains(ext)) {
      category = Category.installers;
    } else if (archiveExt.contains(ext)) {
      category = Category.archives;
    } else if (videoExt.contains(ext)) {
      category = Category.videos;
    } else if (audioExt.contains(ext)) {
      category = Category.audio;
    } else if (pictureExt.contains(ext) || inPictures) {
      category = Category.pictures;
    } else if (documentExt.contains(ext)) {
      category = Category.documents;
    } else {
      category = Category.other;
    }

    return Categorization(
      category: category,
      isProtected: inPictures,
      cloudSynced: cloud,
    );
  }
}
