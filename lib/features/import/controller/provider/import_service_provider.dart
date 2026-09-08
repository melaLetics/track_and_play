import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../database/provider/database_provider.dart';
import '../import_service.dart';

final importServiceProvider = Provider<ImportService>((ref) {
  final db = ref.watch(databaseProvider);
  return ImportService(db);
});
