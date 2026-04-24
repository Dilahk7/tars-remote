import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _hostKey = 'remote_host';
const _tokenKey = 'remote_token';

void main() {
  runApp(const TarsRemoteApp());
}

class TarsRemoteApp extends StatelessWidget {
  const TarsRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7EE7D1),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1020),
    );

    return MaterialApp(
      title: 'TARS Remote',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        cardTheme: baseTheme.cardTheme.copyWith(
          color: const Color(0xFF121A2D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      home: const RemoteHomePage(),
    );
  }
}

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key});

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  final _api = RemoteApi();

  RemoteStatus _status = RemoteStatus.disconnected();
  bool _loaded = false;
  bool _busy = false;
  String? _lastError;
  double? _draftVolume;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  bool get _hasCredentials =>
      _hostController.text.trim().isNotEmpty &&
      _tokenController.text.trim().isNotEmpty;

  double get _sliderValue {
    final raw = _draftVolume ?? _status.volume ?? 50;
    return raw.clamp(0, 100).toDouble();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _hostController.text = prefs.getString(_hostKey) ?? '';
    _tokenController.text = prefs.getString(_tokenKey) ?? '';

    if (!mounted) {
      return;
    }

    setState(() {
      _loaded = true;
    });

    if (_hasCredentials) {
      await _refreshStatus(showError: false);
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, _hostController.text.trim());
    await prefs.setString(_tokenKey, _tokenController.text.trim());
  }

  Future<void> _refreshStatus({bool showError = true}) async {
    if (!_hasCredentials) {
      setState(() {
        _status = RemoteStatus.disconnected(
          message: 'Enter the laptop IP and token.',
        );
        if (showError) {
          _lastError = 'Missing connection details.';
        }
      });
      return;
    }

    setState(() {
      _busy = true;
      if (!showError) {
        _lastError = null;
      }
    });

    try {
      final status = await _api.fetchStatus(
        hostInput: _hostController.text,
        token: _tokenController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _draftVolume = status.volume;
        _lastError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = RemoteStatus.disconnected(message: 'Unable to reach laptop.');
        if (showError) {
          _lastError = error.toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _testAndSave() async {
    FocusScope.of(context).unfocus();
    await _saveSettings();
    await _refreshStatus();
  }

  Future<void> _runCommand(
    String command, {
    Map<String, dynamic>? extra,
  }) async {
    if (!_hasCredentials || !_status.connected) {
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
    });

    try {
      final status = await _api.sendCommand(
        hostInput: _hostController.text,
        token: _tokenController.text,
        command: command,
        extra: extra,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _draftVolume = status.volume;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _setVolume(double value) async {
    if (!_hasCredentials || !_status.connected) {
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
    });

    try {
      final status = await _api.setVolume(
        hostInput: _hostController.text,
        token: _tokenController.text,
        level: value,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _draftVolume = status.volume;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canControl = _status.connected && !_busy;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('TARS Remote'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _busy ? null : _refreshStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _ConnectionCard(
                    hostController: _hostController,
                    tokenController: _tokenController,
                    busy: _busy,
                    status: _status,
                    onChanged: () => setState(() {}),
                    onSaveAndTest: _testAndSave,
                  ),
                  const SizedBox(height: 16),
                  if (_lastError != null) ...[
                    _ErrorBanner(message: _lastError!),
                    const SizedBox(height: 16),
                  ],
                  _StatusCard(status: _status, busy: _busy),
                  const SizedBox(height: 16),
                  _TransportCard(
                    enabled: canControl,
                    onPrevious: () => _runCommand('previous'),
                    onRewind: () =>
                        _runCommand('seek_backward', extra: {'seconds': 15}),
                    onPlayPause: () => _runCommand('play_pause'),
                    onForward: () =>
                        _runCommand('seek_forward', extra: {'seconds': 15}),
                    onNext: () => _runCommand('next'),
                  ),
                  const SizedBox(height: 16),
                  _VolumeCard(
                    enabled: canControl,
                    muted: _status.muted,
                    sliderValue: _sliderValue,
                    onVolumeDown: () => _runCommand('volume_down'),
                    onVolumeUp: () => _runCommand('volume_up'),
                    onMuteToggle: () => _runCommand('mute_toggle'),
                    onSliderChanged: (value) =>
                        setState(() => _draftVolume = value),
                    onSliderChangeEnd: _setVolume,
                  ),
                ],
              ),
            ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.hostController,
    required this.tokenController,
    required this.busy,
    required this.status,
    required this.onChanged,
    required this.onSaveAndTest,
  });

  final TextEditingController hostController;
  final TextEditingController tokenController;
  final bool busy;
  final RemoteStatus status;
  final VoidCallback onChanged;
  final Future<void> Function() onSaveAndTest;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tv_rounded),
                const SizedBox(width: 10),
                Text(
                  'Laptop connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hostController,
              onChanged: (_) => onChanged(),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Laptop IP or URL',
                hintText: '192.168.1.25:8765',
                prefixIcon: Icon(Icons.lan_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              onChanged: (_) => onChanged(),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Shared token',
                hintText: 'Same token you pass to the server',
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onSaveAndTest,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Save & test connection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.busy});

  final RemoteStatus status;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.connected
                      ? Icons.check_circle_rounded
                      : Icons.cloud_off_rounded,
                  color: status.connected
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Text(
                  status.connected
                      ? 'Connected to laptop'
                      : 'Waiting for connection',
                  style: textTheme.titleMedium,
                ),
                if (busy) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              status.message ?? 'Ready when you are.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.volume_up_rounded,
                  label: status.volume != null
                      ? '${status.volume!.round()}%'
                      : 'Unknown volume',
                ),
                _InfoPill(
                  icon: status.muted
                      ? Icons.volume_off_rounded
                      : Icons.music_note_rounded,
                  label: status.muted
                      ? 'Muted'
                      : (status.mediaBackend ?? 'Media backend idle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.enabled,
    required this.onPrevious,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onNext,
  });

  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Playback', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _RoundControlButton(
                    enabled: enabled,
                    icon: Icons.skip_previous_rounded,
                    label: 'Prev',
                    onTap: onPrevious,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RoundControlButton(
                    enabled: enabled,
                    icon: Icons.replay_10_rounded,
                    label: '-15s',
                    onTap: onRewind,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _PrimaryControlButton(
                    enabled: enabled,
                    icon: Icons.play_arrow_rounded,
                    label: 'Play / Pause',
                    onTap: onPlayPause,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RoundControlButton(
                    enabled: enabled,
                    icon: Icons.forward_10_rounded,
                    label: '+15s',
                    onTap: onForward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RoundControlButton(
                    enabled: enabled,
                    icon: Icons.skip_next_rounded,
                    label: 'Next',
                    onTap: onNext,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({
    required this.enabled,
    required this.muted,
    required this.sliderValue,
    required this.onVolumeDown,
    required this.onVolumeUp,
    required this.onMuteToggle,
    required this.onSliderChanged,
    required this.onSliderChangeEnd,
  });

  final bool enabled;
  final bool muted;
  final double sliderValue;
  final VoidCallback onVolumeDown;
  final VoidCallback onVolumeUp;
  final VoidCallback onMuteToggle;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Volume', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                _SmallControlButton(
                  enabled: enabled,
                  icon: Icons.remove_rounded,
                  label: 'Down',
                  onTap: onVolumeDown,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Slider(
                        min: 0,
                        max: 100,
                        value: sliderValue,
                        onChanged: enabled ? onSliderChanged : null,
                        onChangeEnd: enabled ? onSliderChangeEnd : null,
                      ),
                      Text('${sliderValue.round()}%'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SmallControlButton(
                  enabled: enabled,
                  icon: Icons.add_rounded,
                  label: 'Up',
                  onTap: onVolumeUp,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: enabled ? onMuteToggle : null,
                icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
                ),
                label: Text(muted ? 'Unmute' : 'Mute'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryControlButton extends StatelessWidget {
  const _PrimaryControlButton({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 28),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: FilledButton.tonal(
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SmallControlButton extends StatelessWidget {
  const _SmallControlButton({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 56,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon), Text(label)],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final RemoteStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status.connected;
    final color = connected ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        connected ? 'Online' : 'Offline',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class RemoteApi {
  Future<RemoteStatus> fetchStatus({
    required String hostInput,
    required String token,
  }) async {
    final uri = _endpoint(hostInput, '/status');
    final response = await http
        .get(uri, headers: _headers(token))
        .timeout(const Duration(seconds: 3));
    return _parseStatus(response);
  }

  Future<RemoteStatus> sendCommand({
    required String hostInput,
    required String token,
    required String command,
    Map<String, dynamic>? extra,
  }) async {
    final uri = _endpoint(hostInput, '/command');
    final body = {'command': command, ...?extra};
    final response = await http
        .post(uri, headers: _headers(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 3));
    return _parseStatus(response);
  }

  Future<RemoteStatus> setVolume({
    required String hostInput,
    required String token,
    required double level,
  }) async {
    final uri = _endpoint(hostInput, '/volume');
    final response = await http
        .post(uri, headers: _headers(token), body: jsonEncode({'level': level}))
        .timeout(const Duration(seconds: 3));
    return _parseStatus(response);
  }

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${token.trim()}',
  };

  Uri _endpoint(String hostInput, String path) {
    var normalized = hostInput.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    var uri = Uri.parse(normalized);
    uri = uri.hasPort
        ? uri.replace(path: path)
        : uri.replace(port: 8765, path: path);

    return uri;
  }

  RemoteStatus _parseStatus(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['error'] ?? 'Request failed (${response.statusCode}).',
      );
    }

    return RemoteStatus.fromJson(body);
  }
}

class RemoteStatus {
  const RemoteStatus({
    required this.connected,
    required this.muted,
    this.volume,
    this.mediaBackend,
    this.message,
  });

  factory RemoteStatus.fromJson(Map<String, dynamic> json) {
    return RemoteStatus(
      connected: json['ok'] == true,
      muted: json['muted'] == true,
      volume: (json['volume'] as num?)?.toDouble(),
      mediaBackend: json['media_backend'] as String?,
      message: json['message'] as String? ?? json['detail'] as String?,
    );
  }

  factory RemoteStatus.disconnected({String? message}) {
    return RemoteStatus(connected: false, muted: false, message: message);
  }

  final bool connected;
  final bool muted;
  final double? volume;
  final String? mediaBackend;
  final String? message;
}
