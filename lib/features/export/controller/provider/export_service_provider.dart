import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/provider/database_provider.dart';
import '../export_service.dart';

final exportServiceProvider = Provider<ExportService>((ref) {
  final db = ref.watch(databaseProvider);
  return ExportService(db);
});
