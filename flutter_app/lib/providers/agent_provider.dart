import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/agent_state.dart';
import '../services/agent_service.dart' as svc;

class AgentProvider extends ChangeNotifier {
  final svc.AgentService _agentService = svc.AgentService();
  StreamSubscription? _subscription;
  AgentState _state = const AgentState();

  AgentState get state => _state;

  AgentProvider() {
    _subscription = _agentService.stateStream.listen((state) {
      _state = state;
      notifyListeners();
    });
    _agentService.init();
  }

  Future<void> start() async {
    await _agentService.start();
  }

  Future<void> stop() async {
    await _agentService.stop();
  }

  Future<bool> checkHealth() async {
    return _agentService.checkHealth();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _agentService.dispose();
    super.dispose();
  }
}
