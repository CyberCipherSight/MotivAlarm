import 'dart:convert';

/// One work or break block inside an interval session. This is also the
/// exact shape the native `IntervalSessionService` consumes as JSON.
class SessionPhase {
  const SessionPhase({
    required this.label,
    required this.seconds,
    required this.isBreak,
  });

  final String label;
  final int seconds;
  final bool isBreak;

  Map<String, dynamic> toJson() => {
    'label': label,
    'seconds': seconds,
    'isBreak': isBreak,
  };

  SessionPhase copyWith({int? seconds}) =>
      SessionPhase(label: label, seconds: seconds ?? this.seconds, isBreak: isBreak);
}

/// A saved interval-session configuration. Stores the basic inputs plus the
/// optional per-phase overrides from Advanced mode ("custom" durations).
class SessionPreset {
  const SessionPreset({
    required this.id,
    required this.name,
    required this.sets,
    required this.setSeconds,
    required this.breakSeconds,
    this.customPhaseSeconds,
  });

  final String id;
  final String name;
  final int sets;
  final int setSeconds;
  final int breakSeconds;

  /// When Advanced mode was used: the duration of every phase in order
  /// (set 1, break 1, set 2, ...). Null means pure basic mode.
  final List<int>? customPhaseSeconds;

  /// Expands the preset into the ordered phase list the service runs.
  /// No break after the final set.
  List<SessionPhase> buildPhases() {
    final phases = <SessionPhase>[];
    for (var i = 0; i < sets; i++) {
      phases.add(
        SessionPhase(label: 'SET ${i + 1}', seconds: setSeconds, isBreak: false),
      );
      if (i < sets - 1) {
        phases.add(
          SessionPhase(label: 'BREAK ${i + 1}', seconds: breakSeconds, isBreak: true),
        );
      }
    }
    final custom = customPhaseSeconds;
    if (custom != null) {
      for (var i = 0; i < phases.length && i < custom.length; i++) {
        phases[i] = phases[i].copyWith(seconds: custom[i]);
      }
    }
    return phases;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sets': sets,
    'setSeconds': setSeconds,
    'breakSeconds': breakSeconds,
    'customPhaseSeconds': customPhaseSeconds,
  };

  factory SessionPreset.fromJson(Map<String, dynamic> json) => SessionPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    sets: json['sets'] as int? ?? 1,
    setSeconds: json['setSeconds'] as int? ?? 45,
    breakSeconds: json['breakSeconds'] as int? ?? 15,
    customPhaseSeconds: (json['customPhaseSeconds'] as List?)?.cast<int>(),
  );

  String encode() => jsonEncode(toJson());
}

String encodePhasesJson(List<SessionPhase> phases) =>
    jsonEncode(phases.map((phase) => phase.toJson()).toList());
