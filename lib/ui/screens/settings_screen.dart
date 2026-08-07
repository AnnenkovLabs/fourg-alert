/// Full settings screen with provider filter, audio modes, stability, data ranking.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fourg_alert/services/globals.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Stability
  int _stabilitySec = 180;
  bool _useKm = false;
  double _stabilityKm = 3.0;
  int _warningMin = 2;

  // Providers
  bool _vodafone = true;
  bool _kyivstar = true;
  bool _lifecell = true;

  // Audio mode: 0=none, 1=sounds, 2=tts
  int _audioMode = 2;
  // Sound signals
  double _soundVolume = 0.8;
  final Map<String, double> _soundDistances = {
    '5 km': 5.0, '3 km': 3.0, '1 km': 1.0, '500 m': 0.5, 'Now': 0.0,
  };
  // TTS
  double _ttsVolume = 0.9;
  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  String _ttsVoice = '';
  final Map<String, bool> _ttsAlerts = {
    'Blind zone ahead warning': true,
    'Entering blind zone': true,
    'Countdown in blind zone': true,
    '4G restored': true,
    'Stable 4G confirmed': true,
    'Phantom 4G detected': false,
    'WiFi/hotspot connected': true,
    'Route started': false,
    'Route completed': false,
    'Speed changed significantly': false,
    'Low confidence coverage': false,
    'Network switch detected': true,
  };
  List<Map<String, String>> _availableVoices = [];

  // Data ranking
  double _recencyW = 0.25, _samplesW = 0.30, _sourceW = 0.20;
  double _operatorsW = 0.15, _consistencyW = 0.10;

  final FlutterTts _ttsEngine = FlutterTts();

  @override
  void initState() {
    super.initState();
    _load();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await _ttsEngine.getVoices;
      final defaultVoice = await _ttsEngine.getDefaultVoice;
      setState(() {
        _availableVoices = (voices as List).map((v) {
          final m = v as Map;
          return {
            'name': m['name']?.toString() ?? '',
            'locale': m['locale']?.toString() ?? '',
          };
        }).toList();
        if (_ttsVoice.isEmpty) {
          _ttsVoice = defaultVoice?.toString() ?? '';
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _stabilitySec = p.getInt('stability_sec') ?? 180;
      _useKm = p.getBool('use_km') ?? false;
      _stabilityKm = p.getDouble('stability_km') ?? 3.0;
      _warningMin = p.getInt('warning_min') ?? 2;
      _vodafone = p.getBool('op_vodafone') ?? true;
      _kyivstar = p.getBool('op_kyivstar') ?? true;
      _lifecell = p.getBool('op_lifecell') ?? true;
      _audioMode = p.getInt('audio_mode') ?? 2;
      _soundVolume = p.getDouble('sound_vol') ?? 0.8;
      _ttsVolume = p.getDouble('tts_vol') ?? 0.9;
      _ttsRate = p.getDouble('tts_rate') ?? 0.5;
      _ttsPitch = p.getDouble('tts_pitch') ?? 1.0;
      _ttsVoice = p.getString('tts_voice') ?? '';
      _recencyW = p.getDouble('w_recency') ?? 0.25;
      _samplesW = p.getDouble('w_samples') ?? 0.30;
      _sourceW = p.getDouble('w_source') ?? 0.20;
      _operatorsW = p.getDouble('w_operators') ?? 0.15;
      _consistencyW = p.getDouble('w_consistency') ?? 0.10;
      // Load TTS alert toggles
      for (final key in _ttsAlerts.keys) {
        _ttsAlerts[key] = p.getBool('tts_$key') ?? _ttsAlerts[key]!;
      }
    });
    _applyAll();
  }

  Future<void> _save(String key, dynamic val) async {
    final p = await SharedPreferences.getInstance();
    if (val is int) { await p.setInt(key, val); }
    else if (val is double) { await p.setDouble(key, val); }
    else if (val is bool) { await p.setBool(key, val); }
    else if (val is String) { await p.setString(key, val); }
    _applyAll();
  }

  void _applyAll() {
    // Predictor config
    appState.predictor.config = appState.predictor.config.copyWith(
      stabilityThresholdSeconds: _stabilitySec,
      useKmForStability: _useKm,
      stabilityThresholdKm: _stabilityKm,
      useDataRanking: true,
    );

    // Operator filter
    int mask = 0;
    if (_vodafone) mask |= 0x01;
    if (_kyivstar) mask |= 0x02;
    if (_lifecell) mask |= 0x04;
    appState.setOperatorFilter(mask);

    // TTS config
    _ttsEngine.setVolume(_ttsVolume);
    _ttsEngine.setSpeechRate(_ttsRate);
    _ttsEngine.setPitch(_ttsPitch);

    appState.notifications.setAudioEnabled(_audioMode > 0);
    appState.notifications.setVibrateEnabled(true);
  }

  void _previewSound(double distanceKm) {
    // Play a system beep for preview
    HapticFeedback.mediumImpact();
  }

  void _previewTts() async {
    await _ttsEngine.setVolume(_ttsVolume);
    await _ttsEngine.setSpeechRate(_ttsRate);
    await _ttsEngine.setPitch(_ttsPitch);
    await _ttsEngine.speak('Це тестовий запис для перевірки TTS у додатку 4G Alert');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.black),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Providers'),
          const Text('Select which mobile operators to monitor for 4G coverage.', style: _sub),
          const SizedBox(height: 10),
          _providerTile('Vodafone Ukraine', _vodafone, (v) { setState(() => _vodafone = v); _save('op_vodafone', v); }),
          _providerTile('Kyivstar', _kyivstar, (v) { setState(() => _kyivstar = v); _save('op_kyivstar', v); }),
          _providerTile('lifecell', _lifecell, (v) { setState(() => _lifecell = v); _save('op_lifecell', v); }),

          const Divider(height: 32),
          _section('Stability Definition'),
          const Text('"Stable 4G" = continuous 4G for at least this much.', style: _sub),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Use kilometers'), value: _useKm,
            subtitle: Text(_useKm ? '$_stabilityKm km' : '${_stabilitySec}s'),
            onChanged: (v) { setState(() => _useKm = v); _save('use_km', v); },
          ),
          if (_useKm)
            _slider('Distance (km)', _stabilityKm, 1.0, 10.0, 0.5, (v) { setState(() => _stabilityKm = v); _save('stability_km', v); })
          else
            _slider('Time (sec)', _stabilitySec.toDouble(), 60, 600, 30, (v) { setState(() => _stabilitySec = v.toInt()); _save('stability_sec', v.toInt()); }),
          _slider('Warn before (min)', _warningMin.toDouble(), 1, 10, 1, (v) { setState(() => _warningMin = v.toInt()); _save('warning_min', v.toInt()); }),

          const Divider(height: 32),
          _section('Audio Mode'),
          const SizedBox(height: 8),
          _audioModeSelector(),

          if (_audioMode == 1) _buildSoundSettings(),
          if (_audioMode == 2) _buildTtsSettings(),

          const Divider(height: 32),
          _section('Data Ranking Weights'),
          const Text('How factors influence coverage confidence.', style: _sub),
          const SizedBox(height: 10),
          _weightSlider('Recency', _recencyW, (v) { setState(() => _recencyW = v); _save('w_recency', v); }),
          _weightSlider('Sample count', _samplesW, (v) { setState(() => _samplesW = v); _save('w_samples', v); }),
          _weightSlider('Source type', _sourceW, (v) { setState(() => _sourceW = v); _save('w_source', v); }),
          _weightSlider('Operators', _operatorsW, (v) { setState(() => _operatorsW = v); _save('w_operators', v); }),
          _weightSlider('Consistency', _consistencyW, (v) { setState(() => _consistencyW = v); _save('w_consistency', v); }),
          Text('Sum: ${(_recencyW + _samplesW + _sourceW + _operatorsW + _consistencyW).toStringAsFixed(2)}',
              style: TextStyle(color: (_recencyW + _samplesW + _sourceW + _operatorsW + _consistencyW - 1.0).abs() < 0.01 ? Colors.green : Colors.orange, fontWeight: FontWeight.w600)),

          const Divider(height: 32),
          const Text('4G Alert v1.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _section(String t) => Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00C853)));
  static const _sub = TextStyle(color: Colors.grey, fontSize: 12);

  Widget _providerTile(String label, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(label), value: value, dense: true,
      activeTrackColor: const Color(0xFF00C853),
      onChanged: onChanged,
    );
  }

  Widget _audioModeSelector() {
    return Row(
      children: [
        _modeChip('No audio', Icons.volume_off, 0),
        const SizedBox(width: 8),
        _modeChip('Sounds', Icons.notifications_active, 1),
        const SizedBox(width: 8),
        _modeChip('TTS Voice', Icons.record_voice_over, 2),
      ],
    );
  }

  Widget _modeChip(String label, IconData icon, int mode) {
    final active = _audioMode == mode;
    return Expanded(
      child: ChoiceChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: active ? Colors.black : Colors.white70), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.black : Colors.white70))]),
        selected: active,
        selectedColor: const Color(0xFF00C853),
        onSelected: (_) { setState(() => _audioMode = mode); _save('audio_mode', mode); },
        backgroundColor: Colors.white.withValues(alpha: 0.05),
      ),
    );
  }

  // ============================================================
  // SOUND SIGNALS MODE
  // ============================================================
  Widget _buildSoundSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Sound signal distances:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        Text('Configure at what distance each sound plays. Tap to preview.', style: _sub),
        const SizedBox(height: 8),
        ..._soundDistances.entries.map((e) => _soundRow(e.key, e.value)),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Volume: ', style: TextStyle(fontSize: 13)),
            Expanded(
              child: Slider(
                value: _soundVolume, min: 0, max: 1, divisions: 10,
                label: (_soundVolume * 100).toInt().toString(),
                activeColor: const Color(0xFF00C853),
                onChanged: (v) { setState(() => _soundVolume = v); _save('sound_vol', v); },
              ),
            ),
            Text('${(_soundVolume * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => _previewSound(1.0),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Preview all signals'),
        ),
      ],
    );
  }

  Widget _soundRow(String label, double distKm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Slider(
              value: distKm, min: 0, max: 10, divisions: 20,
              label: '${distKm.toStringAsFixed(1)} km',
              activeColor: const Color(0xFFFF9800),
              onChanged: (v) { setState(() => _soundDistances[label] = v); _save('sound_$label', v); },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, size: 18, color: Color(0xFF00C853)),
            onPressed: () => _previewSound(distKm),
            tooltip: 'Preview',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TTS MODE
  // ============================================================
  Widget _buildTtsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('TTS Volume:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Row(children: [
          Expanded(child: Slider(value: _ttsVolume, min: 0, max: 1, divisions: 10, activeColor: const Color(0xFF00C853), onChanged: (v) { setState(() => _ttsVolume = v); _save('tts_vol', v); })),
          Text('${(_ttsVolume * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
        ]),
        const Text('Speech Rate:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Row(children: [
          Expanded(child: Slider(value: _ttsRate, min: 0.1, max: 1.0, divisions: 9, activeColor: const Color(0xFF00C853), onChanged: (v) { setState(() => _ttsRate = v); _save('tts_rate', v); })),
          Text(_ttsRate.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
        ]),
        const Text('Pitch:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Row(children: [
          Expanded(child: Slider(value: _ttsPitch, min: 0.5, max: 2.0, divisions: 15, activeColor: const Color(0xFF00C853), onChanged: (v) { setState(() => _ttsPitch = v); _save('tts_pitch', v); })),
          Text(_ttsPitch.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
        ]),
        if (_availableVoices.isNotEmpty) ...[
          const Text('Voice:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          DropdownButton<String>(
            value: _ttsVoice.isNotEmpty ? _ttsVoice : null,
            isExpanded: true,
            hint: const Text('Select voice'),
            items: _availableVoices.map((v) => DropdownMenuItem(value: v['name'], child: Text('${v['name']} (${v['locale']})', style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) { setState(() => _ttsVoice = v!); _save('tts_voice', v); },
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _previewTts,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Preview TTS'),
        ),
        const SizedBox(height: 12),
        const Text('Alert types for TTS:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        ..._ttsAlerts.entries.map((e) => CheckboxListTile(
          title: Text(e.key, style: const TextStyle(fontSize: 13)),
          value: e.value, dense: true,
          activeColor: const Color(0xFF00C853),
          onChanged: (v) { setState(() => _ttsAlerts[e.key] = v!); _save('tts_${e.key}', v); },
        )),
      ],
    );
  }

  // ============================================================
  // Shared widgets
  // ============================================================
  Widget _slider(String label, double value, double min, double max, double step, Function(double) onChange) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(value.toStringAsFixed(step < 1 ? 1 : 0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
      Slider(value: value, min: min, max: max, divisions: ((max - min) / step).round(), onChanged: onChange, activeColor: const Color(0xFF00C853)),
    ]);
  }

  Widget _weightSlider(String label, double value, Function(double) onChange) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(value.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
      ]),
      Slider(value: value, min: 0.0, max: 1.0, divisions: 20, onChanged: onChange, activeColor: const Color(0xFF00C853)),
    ]);
  }
}
