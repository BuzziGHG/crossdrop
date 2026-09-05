import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Map<String, int> _lastReportedProgress = {};
  final Map<String, DateTime> _lastUpdateTime = {};

  static const String channelId = 'crossdrop_transfers_channel';
  static const String channelName = 'CrossDrop Dateiübertragungen';
  static const String channelDesc = 'Fortschritt aktiver Dateiübertragungen in der Benachrichtigungsleiste';

  Future<void> init() async {
    if (_initialized) return;

    try {
      if (kIsWeb) return;

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const LinuxInitializationSettings linuxSettings =
          LinuxInitializationSettings(defaultActionName: 'CrossDrop öffnen');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        linux: linuxSettings,
      );

      if (Platform.isAndroid || Platform.isLinux) {
        await _notifications.initialize(initSettings);

        if (Platform.isAndroid) {
          final androidImpl = _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          await androidImpl?.requestNotificationsPermission();
        }
      }

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  int _getNotificationId(String taskId) {
    return taskId.hashCode.abs() % 100000;
  }

  Future<void> showTransferProgress({
    required String taskId,
    required String filename,
    required int progressPercent,
    required String speed,
    required String eta,
    required bool isSend,
  }) async {
    if (!_initialized) return;

    final lastProg = _lastReportedProgress[taskId] ?? -1;
    final lastTime = _lastUpdateTime[taskId];
    final now = DateTime.now();

    if (lastTime != null &&
        (progressPercent - lastProg).abs() < 2 &&
        now.difference(lastTime).inMilliseconds < 500 &&
        progressPercent < 100) {
      return;
    }

    _lastReportedProgress[taskId] = progressPercent;
    _lastUpdateTime[taskId] = now;

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    if (kIsWeb || (!Platform.isAndroid && !Platform.isLinux)) return;

    final id = _getNotificationId(taskId);
    final title = isSend ? 'Sende: $filename' : 'Empfange: $filename';
    final etaText = eta.isNotEmpty ? ' • $eta' : '';
    final body = '$progressPercent% • $speed$etaText';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent.clamp(0, 100),
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );

    try {
      await _notifications.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing transfer progress notification: $e');
    }
  }

  Future<void> showTransferCompleted({
    required String taskId,
    required String filename,
    required bool isSend,
  }) async {
    _lastReportedProgress.remove(taskId);
    _lastUpdateTime.remove(taskId);

    try {
      await WakelockPlus.disable();
    } catch (_) {}

    if (!_initialized) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isLinux)) return;

    final id = _getNotificationId(taskId);
    final title = isSend ? 'Datei erfolgreich übertragen ✅' : 'Datei empfangen ✅';
    final body = filename;

    final androidDetails = const AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showProgress: false,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    try {
      await _notifications.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing transfer completed notification: $e');
    }
  }

  Future<void> showTransferFailed({
    required String taskId,
    required String filename,
    required String reason,
  }) async {
    _lastReportedProgress.remove(taskId);
    _lastUpdateTime.remove(taskId);

    try {
      await WakelockPlus.disable();
    } catch (_) {}

    if (!_initialized) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isLinux)) return;

    final id = _getNotificationId(taskId);
    final title = 'Übertragung fehlgeschlagen ❌';
    final body = '$filename: $reason';

    final androidDetails = const AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showProgress: false,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    try {
      await _notifications.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing transfer failed notification: $e');
    }
  }

  Future<void> cancel(String taskId) async {
    _lastReportedProgress.remove(taskId);
    _lastUpdateTime.remove(taskId);
    try {
      await _notifications.cancel(_getNotificationId(taskId));
    } catch (_) {}
  }
}