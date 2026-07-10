import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'queue_provider.dart';

final queueBadgeProvider = Provider<int>((ref) {
  final queueList = ref.watch(queueProvider);
  return queueList.where((item) => item.status == 'pending' || item.status == 'downloading').length;
});
