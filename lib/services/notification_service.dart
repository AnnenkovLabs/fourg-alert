/// Notification service — handles TTS audio announcements and push notifications.
library;

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum AlertType {
  warning, // ⚠️ Approaching no-4G zone
  countdown, // ⏳ In no-4G zone, countdown to restoration
  restored, // ✅ 4G restored
  phantom, // 👻 Phantom 4G detected
}

class NotificationService {
  final FlutterTts _tts = FlutterTts();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _ttsReady = false;
  bool _notificationsReady = false;
  bool _audioEnabled = true;
  bool _vibrateEnabled = true;

  bool get audioEnabled => _audioEnabled;
  bool get vibrateEnabled => _vibrateEnabled;

  Future<void> init() async {
    // Init TTS
    await _tts.setLanguage('uk-UA');
    await _tts.setSpeechRate(0.5); // slightly slower for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsReady = true;

    // Init push notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(initSettings);

    // Create notification channel for ongoing status
    const androidChannel = AndroidNotificationChannel(
      'fourg_alert_channel',
      '4G Alert',
      description: 'Coverage alerts and status',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _notificationsReady = true;
  }

  /// Announce an alert: TTS audio + optional push notification.
  Future<void> announce(AlertType type, String text, {bool push = true}) async {
    // TTS audio
    if (_ttsReady && _audioEnabled) {
      await _tts.speak(text);
    }

    // Push notification (for background/overlay updates)
    if (_notificationsReady && push) {
      await _notifications.show(
        type.index,
        _alertTitle(type),
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'fourg_alert_channel',
            '4G Alerts',
            channelDescription: 'Coverage alerts',
            importance: _vibrateEnabled ? Importance.high : Importance.low,
            priority: Priority.high,
            enableVibration: _vibrateEnabled,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    }
  }

  String _alertTitle(AlertType type) => switch (type) {
    AlertType.warning => '\u26A0\uFE0F 4G Alert',
    AlertType.countdown => '\u23F3 4G Countdown',
    AlertType.restored => '\u2705 4G Restored',
    AlertType.phantom => '\uD83D\uDC7B No Internet',
  };

  /// Show persistent notification for foreground service overlay.
  Future<void> showOngoingStatus(String text) async {
    if (!_notificationsReady) return;
    await _notifications.show(
      999, // persistent ID
      '4G Alert Active',
      text,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fourg_alert_channel',
          '4G Alert',
          channelDescription: 'Ongoing coverage monitoring',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
        iOS: DarwinNotificationDetails(presentAlert: false, presentBadge: false, presentSound: false),
      ),
    );
  }

  void cancelOngoingStatus() {
    _notifications.cancel(999);
  }

  void setAudioEnabled(bool enabled) => _audioEnabled = enabled;
  void setVibrateEnabled(bool enabled) => _vibrateEnabled = enabled;

  Future<void> dispose() async {
    await _tts.stop();
    await _notifications.cancelAll();
  }
}
