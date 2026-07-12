import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),  // Render cold start can take 20-30s
      receiveTimeout: const Duration(seconds: 120),  // Extraction jobs can take 60-90s
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Bypasses SSL certificate verification for environments with invalid/self-signed certs
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );

    // Dynamic Device ID Header Interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final deviceId = prefs.getString(AppConstants.keyDeviceId);
          if (deviceId != null) {
            options.headers['x-device-id'] = deviceId;
          }
        } catch (_) {}
        return handler.next(options);
      },
    ));

    // Retry Interceptor with Exponential Backoff
    _dio.interceptors.add(_RetryInterceptor(_dio));

    // Verbose Network Log Interceptor (debug only)
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) {
          // ignore: avoid_print
          print('[API] $obj');
        },
      ));
    }
  }

  Dio get dio => _dio;

  /// Ping the server health endpoint to wake it up from Render sleep
  Future<bool> wakeUpServer() async {
    try {
      debugPrint('[API] Pinging server health endpoint to wake up...');
      final response = await _dio.get<Map<String, dynamic>>(
        '/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 45), // Extra time for cold start
        ),
      );
      final isOk = response.statusCode == 200;
      debugPrint('[API] Server health: ${isOk ? "OK" : "NOT OK"} (${response.statusCode})');
      return isOk;
    } catch (e) {
      debugPrint('[API] Server wake-up ping failed: $e');
      return false;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> downloadFile(
    String url,
    String savePath, {
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          receiveTimeout: const Duration(seconds: 180), // Large files may take a while
        ),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException e) {
    final statusCode = e.response?.statusCode;
    final requestPath = e.requestOptions.path;
    final requestHost = e.requestOptions.baseUrl;
    
    // Check for HTML error responses from Render/Nginx proxies (502, 503, 504, 404)
    if (statusCode != null) {
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return ApiException('Server is waking up or temporarily unavailable. Please try again.', statusCode);
      }
      if (statusCode == 404) {
        return ApiException("Endpoint '$requestPath' not found. Check your backend deployment.", statusCode);
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('Server is starting up. Please wait and try again.', statusCode);
      case DioExceptionType.receiveTimeout:
        return ApiException('Server is processing your request. It may still complete — check your queue.', statusCode);
      case DioExceptionType.badResponse:
        final message = _extractErrorMessage(e.response);
        if (statusCode == 429) {
          return ApiException('Too many requests. Please wait before trying again.', statusCode);
        }
        if (statusCode != null && statusCode >= 500) {
          return ApiException('Server error ($statusCode). Please try again.', statusCode);
        }
        return ApiException(message, statusCode);
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled.', null);
      case DioExceptionType.connectionError:
        return ApiException('Cannot reach the server. Check your internet connection.', null);
      default:
        // Try to inspect the nested exception for SSL or Socket failures
        final err = e.error;
        if (err != null) {
          final errStr = err.toString();
          if (errStr.contains('HandshakeException') || errStr.contains('CERTIFICATE_VERIFY_FAILED')) {
            return ApiException('SSL certificate error. Try again later.', null);
          }
          if (errStr.contains('SocketException')) {
            return ApiException('Network connection failed. Check your internet.', null);
          }
          return ApiException('Connection failed. Please try again.', null);
        }
        return ApiException('Network error. Please try again.', null);
    }
  }

  String _extractErrorMessage(Response? response) {
    final data = response?.data;
    if (data is Map) {
      return data['error']?.toString() ??
          data['message']?.toString() ??
          'An error occurred';
    }
    if (data is String) {
      if (data.contains('<!DOCTYPE html') || data.contains('<html>')) {
        final match = RegExp(r'<title>([^<]+)</title>', caseSensitive: false).firstMatch(data);
        if (match != null) {
          return 'Server returned: ${match.group(1)}';
        }
        return 'Server returned an error page.';
      }
      return data.length > 150 ? '${data.substring(0, 150)}...' : data;
    }
    return 'An error occurred';
  }
}

/// Automatic retry interceptor with exponential backoff.
/// Retries on timeouts and 5xx errors up to 3 times.
class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const _maxRetries = 3;

  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final shouldRetry = _shouldRetry(err);
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    if (shouldRetry && retryCount < _maxRetries) {
      final nextRetry = retryCount + 1;
      final delayMs = 1000 * (1 << retryCount); // 1s, 2s, 4s
      debugPrint('[API] Retry $nextRetry/$_maxRetries after ${delayMs}ms for ${err.requestOptions.path}');
      
      await Future.delayed(Duration(milliseconds: delayMs));
      
      err.requestOptions.extra['retryCount'] = nextRetry;
      
      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (retryErr) {
        if (retryErr is DioException) {
          handler.next(retryErr);
        } else {
          handler.next(err);
        }
      }
      return;
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    // Retry on timeouts
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    // Retry on 5xx server errors (backend restarting, etc.)
    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500) {
      return true;
    }
    // Retry on connection errors (network blip)
    if (err.type == DioExceptionType.connectionError) {
      return true;
    }
    return false;
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message';
}
