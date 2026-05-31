enum AgentStatus {
  stopped,
  starting,
  running,
  error,
}

class AgentState {
  final AgentStatus status;
  final List<String> logs;
  final String? errorMessage;
  final DateTime? startedAt;
  final String? dashboardUrl;

  const AgentState({
    this.status = AgentStatus.stopped,
    this.logs = const [],
    this.errorMessage,
    this.startedAt,
    this.dashboardUrl,
  });

  AgentState copyWith({
    AgentStatus? status,
    List<String>? logs,
    String? errorMessage,
    bool clearError = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    String? dashboardUrl,
    bool clearDashboardUrl = false,
  }) {
    return AgentState(
      status: status ?? this.status,
      logs: logs ?? this.logs,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      dashboardUrl: clearDashboardUrl ? null : (dashboardUrl ?? this.dashboardUrl),
    );
  }

  bool get isRunning => status == AgentStatus.running;
  bool get isStopped => status == AgentStatus.stopped;

  String get statusText {
    switch (status) {
      case AgentStatus.stopped:
        return 'Stopped';
      case AgentStatus.starting:
        return 'Starting...';
      case AgentStatus.running:
        return 'Running';
      case AgentStatus.error:
        return 'Error';
    }
  }
}
