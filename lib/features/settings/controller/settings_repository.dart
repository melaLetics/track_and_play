import 'package:shared_preferences/shared_preferences.dart';

import '../model/app_settings.dart';

class SettingsRepository {
  static const _kTrackOtherPlayers = 'track_other_players';
  static const _kSelfPlayerId = 'self_player_id';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      trackOtherPlayers: prefs.getBool(_kTrackOtherPlayers) ?? false,
      selfPlayerId: prefs.getInt(_kSelfPlayerId),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrackOtherPlayers, settings.trackOtherPlayers);
    final selfId = settings.selfPlayerId;
    if (selfId != null) {
      await prefs.setInt(_kSelfPlayerId, selfId);
    }
  }
}
