import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/network/extraction_service.dart';
import 'share_intent_provider.dart';
import 'widgets/extraction_bottom_sheet.dart';

final shareIntentHandlerProvider =
    StateNotifierProvider<ShareIntentHandler, ShareIntentState>((ref) {
  return ShareIntentHandler(ref);
});

class ShareIntentState {
  final bool initialized;

  const ShareIntentState({this.initialized = false});
}

class ShareIntentHandler extends StateNotifier<ShareIntentState> {
  final Ref _ref;
  StreamSubscription? _intentSub;

  ShareIntentHandler(this._ref) : super(const ShareIntentState());

  void initialize(BuildContext context) {
    if (state.initialized) return;
    state = const ShareIntentState(initialized: true);

    // Handle intent when app is already running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _handleSharedFiles(context, files);
      },
    );

    // Handle intent when app is launched via share
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(context, files);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  void _handleSharedFiles(BuildContext context, List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    for (final file in files) {
      String? url;
      String? localPath;
      String platform = 'local';

      if (file.type == SharedMediaType.url ||
          file.type == SharedMediaType.text) {
        // Shared a URL (most common for reels)
        url = file.path;
        platform = ExtractionService.detectPlatform(url);
      } else if (file.type == SharedMediaType.video ||
          file.type == SharedMediaType.file) {
        // Shared a local video file
        localPath = file.path;
        platform = 'local';
      }

      if (url != null || localPath != null) {
        // Show the extraction bottom sheet
        _ref.read(extractionFlowProvider.notifier).startExtraction(
              url: url,
              localPath: localPath,
              platform: platform,
            );

        if (context.mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            backgroundColor: Colors.transparent,
            builder: (_) => const ExtractionBottomSheet(),
          );
        }
        break; // Handle one at a time
      }
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }
}
