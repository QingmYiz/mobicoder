import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/agent_state.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';

class AgentService {
  Timer? _healthTimer;
  Timer? _initialDelayTimer;
  StreamSubscription? _logSubscription;
  final _stateController = StreamController<AgentState>.broadcast();
  AgentState _state = const AgentState();
  DateTime? _startingAt;
  bool _startInProgress = false;

  static String _ts(String msg) =>
      '${DateTime.now().toUtc().toIso8601String()} $msg';

  Stream<AgentState> get stateStream => _stateController.stream;
  AgentState get state => _state;

  void _updateState(AgentState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  Future<void> init() async {
    final prefs = PreferencesService();
    await prefs.init();

    try { await NativeBridge.setupDirs(); } catch (_) {}
    try { await NativeBridge.writeResolv(); } catch (_) {}

    try {
      final filesDir = await NativeBridge.getFilesDir();
      const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
      final resolvFile = File('$filesDir/config/resolv.conf');
      if (!resolvFile.existsSync()) {
        Directory('$filesDir/config').createSync(recursive: true);
        resolvFile.writeAsStringSync(resolvContent);
      }
      final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
      if (!rootfsResolv.existsSync()) {
        rootfsResolv.parent.createSync(recursive: true);
        rootfsResolv.writeAsStringSync(resolvContent);
      }
    } catch (_) {}

    final alreadyRunning = await NativeBridge.isAgentRunning();
    if (alreadyRunning) {
      _startingAt = DateTime.now();
      _updateState(_state.copyWith(
        status: AgentStatus.starting,
        logs: [..._state.logs, _ts('[INFO] Agent process detected, reconnecting...')],
      ));
      _subscribeLogs();
      _startHealthCheck();
    } else if (prefs.autoStartGateway) {
      _updateState(_state.copyWith(
        logs: [..._state.logs, _ts('[INFO] Auto-starting agent...')],
      ));
      await start();
    }
  }

  void _subscribeLogs() {
    _logSubscription?.cancel();
    _logSubscription = NativeBridge.agentLogStream.listen((log) {
      final logs = [..._state.logs, log];
      if (logs.length > 500) {
        logs.removeRange(0, logs.length - 500);
      }
      _updateState(_state.copyWith(logs: logs));
    });
  }

  Future<void> start() async {
    if (_startInProgress) return;
    _startInProgress = true;

    final prefs = PreferencesService();
    await prefs.init();
    prefs.dashboardUrl = null;

    _updateState(_state.copyWith(
      status: AgentStatus.starting,
      clearError: true,
      clearDashboardUrl: true,
      logs: [..._state.logs, _ts('[INFO] Starting agent...')],
    ));

    try {
      try { await NativeBridge.setupDirs(); } catch (_) {}
      try { await NativeBridge.writeResolv(); } catch (_) {}
      try {
        final filesDir = await NativeBridge.getFilesDir();
        const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
        final resolvFile = File('$filesDir/config/resolv.conf');
        if (!resolvFile.existsSync()) {
          Directory('$filesDir/config').createSync(recursive: true);
          resolvFile.writeAsStringSync(resolvContent);
        }
        final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
        if (!rootfsResolv.existsSync()) {
          rootfsResolv.parent.createSync(recursive: true);
          rootfsResolv.writeAsStringSync(resolvContent);
        }
      } catch (_) {}

      _startingAt = DateTime.now();
      await NativeBridge.startAgent();
      _subscribeLogs();
      _startHealthCheck();
    } catch (e) {
      _updateState(_state.copyWith(
        status: AgentStatus.error,
        errorMessage: 'Failed to start: $e',
        logs: [..._state.logs, _ts('[ERROR] Failed to start: $e')],
      ));
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    _cancelAllTimers();
    _logSubscription?.cancel();
    _startingAt = null;

    try {
      await NativeBridge.stopAgent();
      _updateState(AgentState(
        status: AgentStatus.stopped,
        logs: [..._state.logs, _ts('[INFO] Agent stopped')],
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        status: AgentStatus.error,
        errorMessage: 'Failed to stop: $e',
      ));
    }
  }

  void _cancelAllTimers() {
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _startHealthCheck() {
    _cancelAllTimers();
    _initialDelayTimer = Timer(const Duration(seconds: 15), () {
      _initialDelayTimer = null;
      if (_state.status == AgentStatus.stopped) return;
      _checkHealth();
      _healthTimer = Timer.periodic(
        const Duration(milliseconds: AppConstants.healthCheckIntervalMs),
        (_) => _checkHealth(),
      );
    });
  }

  Future<void> _checkHealth() async {
    try {
      // OpenClaw gateway health: just check if the port is accessible.
      // OpenClaw does not expose /api/health; any 2xx/3xx/4xx means the
      // gateway is listening.
      final response = await http
          .get(Uri.parse(AppConstants.agentUrl))
          .timeout(const Duration(seconds: 3));

      if (_state.status != AgentStatus.running) {
        _updateState(_state.copyWith(
          status: AgentStatus.running,
          startedAt: DateTime.now(),
          logs: [..._state.logs, _ts('[INFO] OpenClaw Gateway 已就绪')],
        ));
      }
    } catch (_) {
      final isRunning = await NativeBridge.isAgentRunning();
      if (!isRunning && _state.status != AgentStatus.stopped) {
        if (_startingAt != null &&
            _state.status == AgentStatus.starting &&
            DateTime.now().difference(_startingAt!).inSeconds < 60) {
          _updateState(_state.copyWith(
            logs: [
              ..._state.logs,
              _ts('[INFO] Starting, waiting for gateway...')
            ],
          ));
          return;
        }
        _updateState(_state.copyWith(
          status: AgentStatus.stopped,
          logs: [
            ..._state.logs,
            _ts('[WARN] OpenClaw Gateway 进程未运行')
          ],
        ));
        _cancelAllTimers();
      }
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse(AppConstants.agentUrl))
          .timeout(const Duration(seconds: 3));
      // Any response means the port is open
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _cancelAllTimers();
    _logSubscription?.cancel();
    _stateController.close();
  }
}
