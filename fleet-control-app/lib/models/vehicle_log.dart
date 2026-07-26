class VehicleLog {
  final int? id;
  final String agentName;
  final String actionType; // Ex: 'Saída de Viatura', 'Devolução de Viatura', 'Abastecimento', etc.
  final String placa;
  final String modelo;
  final int? quilometragem;
  final DateTime timestamp;
  final String observations;

  VehicleLog({
    this.id,
    required this.agentName,
    required this.actionType,
    this.placa = '',
    this.modelo = '',
    this.quilometragem,
    required this.timestamp,
    required this.observations,
  });

  factory VehicleLog.fromJson(Map<String, dynamic> json) {
    return VehicleLog(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      agentName: json['agente_nome'] ?? '',
      actionType: json['tipo_movimento'] ?? '',
      placa: json['placa'] ?? '',
      modelo: json['modelo'] ?? '',
      quilometragem: json['quilometragem'] is int
          ? json['quilometragem']
          : int.tryParse(json['quilometragem']?.toString() ?? ''),
      timestamp: json['data_hora_saida'] != null
          ? DateTime.tryParse(json['data_hora_saida']) ?? DateTime.now()
          : DateTime.now(),
      observations: json['observacoes'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agente_nome': agentName,
      'tipo_movimento': actionType,
      'placa': placa,
      'modelo': modelo,
      'quilometragem': quilometragem,
      'data_hora_saida': timestamp.toIso8601String(),
      'observacoes': observations,
    };
  }
}
