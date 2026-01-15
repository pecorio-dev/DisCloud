import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BandwidthMode {
  unlimited,
  limited,
  auto50percent,
}

class BandwidthConfig {
  final BandwidthMode mode;
  final double uploadLimitMBps;
  final double downloadLimitMBps;
  final double measuredSpeedMBps;

  const BandwidthConfig({
    this.mode = BandwidthMode.unlimited,
    this.uploadLimitMBps = 0,
    this.downloadLimitMBps = 0,
    this.measuredSpeedMBps = 0,
  });

  int get uploadBytesPerSecond => 
      mode == BandwidthMode.unlimited ? 0 : (uploadLimitMBps * 1024 * 1024).toInt();
  
  int get downloadBytesPerSecond => 
      mode == BandwidthMode.unlimited ? 0 : (downloadLimitMBps * 1024 * 1024).toInt();

  BandwidthConfig copyWith({
    BandwidthMode? mode,
    double? uploadLimitMBps,
    double? downloadLimitMBps,
    double? measuredSpeedMBps,
  }) {
    return BandwidthConfig(
      mode: mode ?? this.mode,
      uploadLimitMBps: uploadLimitMBps ?? this.uploadLimitMBps,
      downloadLimitMBps: downloadLimitMBps ?? this.downloadLimitMBps,
      measuredSpeedMBps: measuredSpeedMBps ?? this.measuredSpeedMBps,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.index,
    'uploadLimitMBps': uploadLimitMBps,
    'downloadLimitMBps': downloadLimitMBps,
    'measuredSpeedMBps': measuredSpeedMBps,
  };

  factory BandwidthConfig.fromJson(Map<String, dynamic> json) {
    return BandwidthConfig(
      mode: BandwidthMode.values[json['mode'] ?? 0],
      uploadLimitMBps: (json['uploadLimitMBps'] ?? 0).toDouble(),
      downloadLimitMBps: (json['downloadLimitMBps'] ?? 0).toDouble(),
      measuredSpeedMBps: (json['measuredSpeedMBps'] ?? 0).toDouble(),
    );
  }
}

class BandwidthService {
  static const String _configKey = 'bandwidth_config';
  BandwidthConfig _config = const BandwidthConfig();
  final Dio _dio = Dio();

  BandwidthConfig get config => _config;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_configKey);
    if (json != null) {
      try {
        _config = BandwidthConfig.fromJson(
          Map<String, dynamic>.from(Uri.splitQueryString(json).map((k, v) => MapEntry(k, num.tryParse(v) ?? v)))
        );
      } catch (e) {}
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, _config.toJson().entries.map((e) => '${e.key}=${e.value}').join('&'));
  }

  Future<void> setMode(BandwidthMode mode) async {
    _config = _config.copyWith(mode: mode);
    await save();
  }

  Future<void> setLimits(double uploadMBps, double downloadMBps) async {
    _config = _config.copyWith(
      mode: BandwidthMode.limited,
      uploadLimitMBps: uploadMBps,
      downloadLimitMBps: downloadMBps,
    );
    await save();
  }

  Future<double> testConnectionSpeed() async {
    const testUrl = 'https://cdn.discordapp.com/attachments/test';
    const testSize = 1 * 1024 * 1024;

    try {
      final startTime = DateTime.now();
      await _dio.get(
        'https://speed.cloudflare.com/__down?bytes=$testSize',
        options: Options(responseType: ResponseType.bytes),
      );
      final endTime = DateTime.now();
      final durationSeconds = endTime.difference(startTime).inMilliseconds / 1000;
      final speedMBps = (testSize / 1024 / 1024) / durationSeconds;
      
      _config = _config.copyWith(measuredSpeedMBps: speedMBps);
      await save();
      
      return speedMBps;
    } catch (e) {
      return 0;
    }
  }

  Future<void> setAuto50Percent() async {
    final speed = await testConnectionSpeed();
    if (speed > 0) {
      final halfSpeed = speed * 0.5;
      _config = _config.copyWith(
        mode: BandwidthMode.auto50percent,
        uploadLimitMBps: halfSpeed,
        downloadLimitMBps: halfSpeed,
        measuredSpeedMBps: speed,
      );
      await save();
    }
  }

  Duration getDelayForChunk(int chunkSize, bool isUpload) {
    if (_config.mode == BandwidthMode.unlimited) {
      return Duration.zero;
    }

    final limitBps = isUpload ? _config.uploadBytesPerSecond : _config.downloadBytesPerSecond;
    if (limitBps <= 0) return Duration.zero;

    final expectedSeconds = chunkSize / limitBps;
    return Duration(milliseconds: (expectedSeconds * 1000).toInt());
  }
}
