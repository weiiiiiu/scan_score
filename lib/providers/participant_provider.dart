import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/participant.dart';
import '../services/csv_service.dart';
import '../services/file_service.dart';
import '../services/storage_service.dart';

/// 参赛者数据状态管理
/// 负责管理所有参赛者数据的增删改查和统计
class ParticipantProvider extends ChangeNotifier {
  final CsvService _csvService;
  final FileService _fileService;
  final StorageService _storageService;

  List<Participant> _participants = [];
  bool _isLoading = false;
  String? _error;

  ParticipantProvider(
    this._csvService,
    this._fileService,
    this._storageService,
  );

  // ===== Getters =====

  List<Participant> get participants => _participants;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasData => _participants.isNotEmpty;

  // 统计信息
  int get totalCount => _participants.length;
  int get checkedInCount =>
      _participants.where((p) => p.checkStatus == 1).length;
  int get uncheckedCount => totalCount - checkedInCount;
  int get scoredCount => _participants.where((p) => p.score != null).length;

  // 加载 CSV 数据
  Future<void> loadData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 检查工作 CSV 是否存在
      if (!await _csvService.hasWorkingCsv()) {
        _participants = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 加载工作 CSV
      _participants = await _csvService.loadWorkingCsv();
      _error = null;
    } catch (e) {
      _error = '加载数据失败: $e';
      _participants = [];
      print(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 导入新的 CSV 文件
  /// 会先清空所有旧数据（包括评分照片）再导入新数据
  Future<bool> importCsv() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final path = await _csvService.importCsv();
      if (path == null) {
        // 用户取消
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 导入成功后，清空旧的评分照片
      await _clearEvidencePhotos();

      // 重新加载数据
      await loadData();
      return true;
    } catch (e) {
      _error = '导入 CSV 失败: $e';
      print(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 清空所有评分照片
  Future<void> _clearEvidencePhotos() async {
    try {
      final evidenceDir = await _storageService.getEvidenceDirectory();
      final dir = Directory(evidenceDir);
      if (await dir.exists()) {
        // 删除目录下所有文件
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      print('清空评分照片失败: $e');
      // 不抛出异常，继续执行
    }
  }

  /// 导出 CSV 和照片
  Future<String?> exportData() async {
    try {
      return await _csvService.exportCsv(_participants);
    } catch (e) {
      _error = '导出数据失败: $e';
      print(_error);
      notifyListeners();
      return null;
    }
  }

  // ===== 数据查询 =====

  /// 根据选手码查找参赛者
  Participant? findByMemberCode(String memberCode) {
    try {
      return _participants.firstWhere((p) => p.memberCode == memberCode);
    } catch (e) {
      return null;
    }
  }

  /// 根据作品码查找参赛者
  Participant? findByWorkCode(String workCode) {
    try {
      return _participants.firstWhere((p) => p.workCode == workCode);
    } catch (e) {
      return null;
    }
  }

  /// 根据 ID 查找参赛者
  Participant? findById(int id) {
    try {
      return _participants.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取所有已评分的参赛者
  List<Participant> getScoredParticipants() {
    return _participants.where((p) => p.score != null).toList();
  }

  /// 获取所有未评分的参赛者
  List<Participant> getUnscoredParticipants() {
    return _participants.where((p) => p.score == null).toList();
  }

  /// 根据姓名或选手码搜索
  List<Participant> search(String query) {
    if (query.isEmpty) return _participants;

    final lowerQuery = query.toLowerCase();
    return _participants.where((p) {
      return p.name.toLowerCase().contains(lowerQuery) ||
          p.memberCode.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  // ===== 数据更新 =====

  /// 更新单个参赛者数据
  Future<void> updateParticipant(Participant participant) async {
    try {
      final index = _participants.indexWhere((p) => p.id == participant.id);

      if (index == -1) {
        throw Exception('参赛者不存在: ID ${participant.id}');
      }

      _participants[index] = participant;

      // 保存到 CSV
      await _csvService.saveWorkingCsv(_participants);

      notifyListeners();
    } catch (e) {
      _error = '更新数据失败: $e';
      print(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// 检录：绑定作品码
  Future<void> bindWorkCode(String memberCode, String workCode) async {
    try {
      final participant = findByMemberCode(memberCode);
      if (participant == null) {
        throw Exception('选手不存在: $memberCode');
      }

      // 检查作品码是否已被使用
      final existingParticipant = findByWorkCode(workCode);
      if (existingParticipant != null &&
          existingParticipant.id != participant.id) {
        throw Exception('作品码已被使用: $workCode');
      }

      final updated = participant.copyWith(workCode: workCode, checkStatus: 1);

      await updateParticipant(updated);
    } catch (e) {
      _error = '绑定作品码失败: $e';
      print(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// 提交评分（处理照片更新逻辑）
  Future<void> submitScore(
    String workCode,
    double score,
    String newPhotoPath,
  ) async {
    try {
      final participant = findByWorkCode(workCode);
      if (participant == null) {
        throw Exception('作品不存在: $workCode');
      }

      // 如果存在旧照片，删除它
      if (participant.evidenceImg != null &&
          participant.evidenceImg!.isNotEmpty) {
        try {
          await _fileService.deleteFile(participant.evidenceImg!);
        } catch (e) {
          print('删除旧照片失败: $e');
          // 继续执行，不抛出异常
        }
      }

      // 更新参赛者数据
      final updated = participant.copyWith(
        score: score,
        evidenceImg: newPhotoPath,
      );

      await updateParticipant(updated);
    } catch (e) {
      _error = '提交评分失败: $e';
      print(_error);
      notifyListeners();
      rethrow;
    }
  }

  // ===== 辅助方法 =====

  /// 清空所有数据
  Future<void> clearData() async {
    _participants = [];
    _error = null;
    await _storageService.clearAllData();
    notifyListeners();
  }

  /// 刷新数据
  Future<void> refresh() async {
    await loadData();
  }
}
