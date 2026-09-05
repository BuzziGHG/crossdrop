class AppConstants {
  static const String appName = 'CrossDrop';
  static const String appVersion = '1.0.2';

  // Default network port for direct peer-to-peer file transfer
  static const int defaultTransferPort = 52520;

  // Heartbeat interval in seconds
  static const int heartbeatIntervalSeconds = 15;

  // Storage keys
  static const String keyServerUrl = 'crossdrop_server_url';
  static const String keyAuthToken = 'crossdrop_auth_token';
  static const String keyUserEmail = 'crossdrop_user_email';
  static const String keyUsername = 'crossdrop_username';
  static const String keyUserId = 'crossdrop_user_id';
  static const String keyDeviceId = 'crossdrop_device_id';
  static const String keyDeviceName = 'crossdrop_device_name';
  static const String keyDownloadPath = 'crossdrop_download_path';
  static const String keyAutoAccept = 'crossdrop_auto_accept';
  static const String keyTransferPort = 'crossdrop_transfer_port';
}
