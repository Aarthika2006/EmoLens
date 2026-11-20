/// Camera settings model for ESP32-CAM status/control.
class CameraSettings {
  final int framesize;
  final int quality;
  final int brightness;
  final int contrast;
  final int saturation;
  final int specialEffect;
  final int whiteBalance;
  final int awbGain;
  final int wbMode;
  final int exposureCtrl;
  final int aecValue;
  final int ae2;
  final int aeLevel;
  final int agcCtrl;
  final int agcGain;
  final int gainCeiling;
  final int bpc;
  final int wpc;
  final int rawGma;
  final int lenc;
  final int hmirror;
  final int vflip;
  final int dcw;
  final int colorbar;
  final int ledIntensity;

  const CameraSettings({
    this.framesize = 8,
    this.quality = 10,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.specialEffect = 0,
    this.whiteBalance = 1,
    this.awbGain = 1,
    this.wbMode = 0,
    this.exposureCtrl = 1,
    this.aecValue = 300,
    this.ae2 = 0,
    this.aeLevel = 0,
    this.agcCtrl = 1,
    this.agcGain = 0,
    this.gainCeiling = 0,
    this.bpc = 0,
    this.wpc = 1,
    this.rawGma = 1,
    this.lenc = 1,
    this.hmirror = 0,
    this.vflip = 0,
    this.dcw = 1,
    this.colorbar = 0,
    this.ledIntensity = 0,
  });

  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      framesize: _parseInt(json, 'framesize', 8),
      quality: _parseInt(json, 'quality', 10),
      brightness: _parseInt(json, 'brightness', 0),
      contrast: _parseInt(json, 'contrast', 0),
      saturation: _parseInt(json, 'saturation', 0),
      specialEffect: _parseInt(json, 'special_effect', 0),
      whiteBalance: _parseInt(json, 'wb_mode', 1),
      awbGain: _parseInt(json, 'awb_gain', 1),
      wbMode: _parseInt(json, 'wb_mode', 0),
      exposureCtrl: _parseInt(json, 'exposure_ctrl', 1),
      aecValue: _parseInt(json, 'aec_value', 300),
      ae2: _parseInt(json, 'aec2', 0),
      aeLevel: _parseInt(json, 'ae_level', 0),
      agcCtrl: _parseInt(json, 'agc_ctrl', 1),
      agcGain: _parseInt(json, 'agc_gain', 0),
      gainCeiling: _parseInt(json, 'gainceiling', 0),
      bpc: _parseInt(json, 'bpc', 0),
      wpc: _parseInt(json, 'wpc', 1),
      rawGma: _parseInt(json, 'raw_gma', 1),
      lenc: _parseInt(json, 'lenc', 1),
      hmirror: _parseInt(json, 'hmirror', 0),
      vflip: _parseInt(json, 'vflip', 0),
      dcw: _parseInt(json, 'dcw', 1),
      colorbar: _parseInt(json, 'colorbar', 0),
      ledIntensity: _parseInt(json, 'led_intensity', 0),
    );
  }

  static int _parseInt(Map<String, dynamic> json, String key, int fallback) {
    final val = json[key];
    if (val is int) return val;
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  Map<String, dynamic> toJson() => {
        'framesize': framesize,
        'quality': quality,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'special_effect': specialEffect,
        'wb_mode': wbMode,
        'awb_gain': awbGain,
        'exposure_ctrl': exposureCtrl,
        'aec_value': aecValue,
        'aec2': ae2,
        'ae_level': aeLevel,
        'agc_ctrl': agcCtrl,
        'agc_gain': agcGain,
        'gainceiling': gainCeiling,
        'bpc': bpc,
        'wpc': wpc,
        'raw_gma': rawGma,
        'lenc': lenc,
        'hmirror': hmirror,
        'vflip': vflip,
        'dcw': dcw,
        'colorbar': colorbar,
        'led_intensity': ledIntensity,
      };
}
