import 'dart:io';
import 'package:path/path.dart' as path;

// 文件管理服务

class FileService {
  // 创建目录
  Future<void> createDirectory(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  // 复制文件
  Future<void> copyFile(String sourcePath, String destinationPath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('源文件不存在: $sourcePath');
    }

    // 确保目标目录存在
    final destDir = path.dirname(destinationPath);
    await createDirectory(destDir);

    await sourceFile.copy(destinationPath);
  }

  // 删除文件
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // 删除目录
  Future<void> deleteDirectory(String dirPath) async {
    final directory = Directory(dirPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  // 重命名/移动文件
  Future<String> renameFile(String oldPath, String newPath) async {
    final file = File(oldPath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $oldPath');
    }

    // 确保目标目录存在
    final destDir = path.dirname(newPath);
    await createDirectory(destDir);

    final renamedFile = await file.rename(newPath);
    return renamedFile.path;
  }

  // 获取目录下的所有文件
  Future<List<String>> listFiles(String dirPath, {String? extension}) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      return [];
    }

    final files = <String>[];
    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is File) {
        if (extension == null ||
            path.extension(entity.path).toLowerCase() == extension) {
          files.add(entity.path);
        }
      }
    }

    return files;
  }

  // 根据作品码查找照片文件
  // 照片命名格式: workCode_score.jpg
  Future<String?> findPhotoByWorkCode(
    String evidenceDir,
    String workCode,
  ) async {
    final files = await listFiles(evidenceDir, extension: '.jpg');

    for (final filePath in files) {
      final fileName = path.basenameWithoutExtension(filePath);
      // 检查文件名是否以 workCode_ 开头
      if (fileName.startsWith('${workCode}_')) {
        return filePath;
      }
    }

    return null;
  }

  // 检查文件是否存在
  Future<bool> fileExists(String filePath) async {
    return await File(filePath).exists();
  }

  // 检查目录是否存在
  Future<bool> directoryExists(String dirPath) async {
    return await Directory(dirPath).exists();
  }

  // 获取文件大小（字节）
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }
    return await file.length();
  }

  // 获取目录大小（所有文件总和）
  Future<int> getDirectorySize(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      return 0;
    }

    int totalSize = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  // 复制整个目录
  Future<void> copyDirectory(String sourcePath, String destinationPath) async {
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) {
      throw Exception('源目录不存在: $sourcePath');
    }

    // 创建目标目录
    await createDirectory(destinationPath);

    // 递归复制所有文件和子目录
    await for (final entity in sourceDir.list(recursive: false)) {
      final entityName = path.basename(entity.path);
      final destPath = path.join(destinationPath, entityName);

      if (entity is File) {
        await copyFile(entity.path, destPath);
      } else if (entity is Directory) {
        await copyDirectory(entity.path, destPath);
      }
    }
  }
}
