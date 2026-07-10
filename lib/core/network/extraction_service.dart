import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import 'api_client.dart';

final extractionServiceProvider = Provider<ExtractionService>((ref) {
  return ExtractionService(ref.watch(apiClientProvider));
});

/// Represents the state of an extraction job
class ExtractionJob {
  final String jobId;
  final ExtractionStatus status;
  final String? downloadUrl;
  final String? error;
  final String? title;

  const ExtractionJob({
    required this.jobId,
    required this.status,
    this.downloadUrl,
    this.error,
    this.title,
  });

  factory ExtractionJob.fromJson(Map<String, dynamic> json) {
    return ExtractionJob(
      jobId: json['jobId'] as String,
      status: ExtractionStatus.fromString(json['status'] as String),
      downloadUrl: json['downloadUrl'] as String?,
      error: json['error'] as String?,
      title: json['title'] as String?,
    );
  }
}

enum ExtractionStatus {
  pending,
  processing,
  completed,
  failed;

  static ExtractionStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return ExtractionStatus.pending;
      case 'processing':
        return ExtractionStatus.processing;
      case 'completed':
        return ExtractionStatus.completed;
      case 'failed':
        return ExtractionStatus.failed;
      default:
        return ExtractionStatus.pending;
    }
  }
}

class ExtractionService {
  final ApiClient _apiClient;
  static const _uuid = Uuid();

  ExtractionService(this._apiClient);

  /// Get or create a persistent device ID for rate limiting
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(AppConstants.keyDeviceId);
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await prefs.setString(AppConstants.keyDeviceId, deviceId);
    }
    return deviceId;
  }

  /// Submit a URL for audio extraction
  Future<String> submitExtraction(String url, {String? quality}) async {
    final deviceId = await _getDeviceId();

    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/extract',
      data: {
        'url': url,
        'deviceId': deviceId,
        if (quality != null) 'quality': quality,
      },
    );

    final data = response.data;
    if (data == null || !data.containsKey('jobId')) {
      throw ApiException('Invalid response from server', null);
    }

    return data['jobId'] as String;
  }

  /// Poll the status of an extraction job
  Future<ExtractionJob> pollStatus(String jobId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/status/$jobId',
    );

    final data = response.data;
    if (data == null) {
      throw ApiException('Invalid response from server', null);
    }

    return ExtractionJob.fromJson(data);
  }

  /// Download the extracted audio file to local storage
  Future<void> downloadAudio(
    String signedUrl,
    String localPath, {
    void Function(double progress)? onProgress,
  }) async {
    await _apiClient.downloadFile(
      signedUrl,
      localPath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
  }

  /// Detect the source platform from a URL
  static String detectPlatform(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('instagram.com') || lowerUrl.contains('instagr.am')) {
      return AppConstants.platformInstagram;
    }
    if (lowerUrl.contains('tiktok.com') || lowerUrl.contains('vm.tiktok.com')) {
      return AppConstants.platformTiktok;
    }
    if (lowerUrl.contains('youtube.com') ||
        lowerUrl.contains('youtu.be') ||
        lowerUrl.contains('youtube.com/shorts')) {
      return AppConstants.platformYoutube;
    }
    if (lowerUrl.contains('facebook.com') ||
        lowerUrl.contains('fb.watch') ||
        lowerUrl.contains('fb.com')) {
      return AppConstants.platformFacebook;
    }
    return AppConstants.platformLocal;
  }

  /// Generate a title from a URL
  static String generateTitle(String url) {
    final platform = detectPlatform(url);
    final timestamp = DateTime.now();
    final timeStr =
        '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';

    switch (platform) {
      case AppConstants.platformInstagram:
        return 'Instagram Reel • $timeStr';
      case AppConstants.platformTiktok:
        return 'TikTok • $timeStr';
      case AppConstants.platformYoutube:
        return 'YouTube Short • $timeStr';
      case AppConstants.platformFacebook:
        return 'Facebook Reel • $timeStr';
      default:
        return 'Audio Clip • $timeStr';
    }
  }
}
