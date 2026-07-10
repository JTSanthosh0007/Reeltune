import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
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

    // Verbose Network Log Interceptor
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) {
        // ignore: avoid_print
        print('[API] $obj');
      },
    ));
  }

  Dio get dio => _dio;

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
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException e) {
    final statusCode = e.response?.statusCode;
    
    // Check for HTML error responses from Render/Nginx proxies (502, 503, 504, 404)
    if (statusCode != null) {
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return ApiException('Backend service is booting up or temporarily offline. Please retry in 30 seconds.', statusCode);
      }
      if (statusCode == 404) {
        return ApiException('API endpoint not found on server (404). Check backend route configuration.', statusCode);
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out. The backend server is taking too long to respond.', statusCode);
      case DioExceptionType.badResponse:
        final message = _extractErrorMessage(e.response);
        if (statusCode == 429) {
          return ApiException('Rate limit exceeded. Please wait before trying again.', statusCode);
        }
        if (statusCode != null && statusCode >= 500) {
          return ApiException('Server Internal Error ($statusCode): $message', statusCode);
        }
        return ApiException(message, statusCode);
      case DioExceptionType.cancel:
        return ApiException('Request was cancelled.', null);
      case DioExceptionType.connectionError:
        return ApiException('Backend service is currently offline or unreachable. Please verify the API server is running.', null);
      default:
        // Try to inspect the nested exception for SSL or Socket failures
        final err = e.error;
        if (err != null) {
          final errStr = err.toString();
          if (errStr.contains('HandshakeException') || errStr.contains('CERTIFICATE_VERIFY_FAILED')) {
            return ApiException('SSL certificate verification failed. Check the backend SSL/TLS certificate configuration.', null);
          }
          if (errStr.contains('SocketException')) {
            return ApiException('Network connection failed (unreachable host or socket error). Verify device connectivity.', null);
          }
          return ApiException('Connection failed: $errStr', null);
        }
        return ApiException('Network request failed: ${e.message ?? 'Unknown connection error'}', null);
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
          return 'HTML Error Page: ${match.group(1)}';
        }
        return 'Server returned an HTML error page.';
      }
      return data.length > 150 ? '${data.substring(0, 150)}...' : data;
    }
    return 'An error occurred';
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}
