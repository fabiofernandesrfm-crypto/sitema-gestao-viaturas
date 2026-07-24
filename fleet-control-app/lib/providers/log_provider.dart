import 'package:flutter/foundation.dart';
import '../models/vehicle_log.dart';
import '../services/api_service.dart';

class LogProvider extends ChangeNotifier {
  final List<VehicleLog> _logs = [];
  bool _isLoading = false;

  List<VehicleLog> get logs => List.unmodifiable(_logs);
  bool get isLoading => _isLoading;

  void addLog({
    required String agentName,
    required String actionType,
    required String observations,
    String placa = '',
    String modelo = '',
    int? quilometragem,
  }) {
    _logs.insert(
      0, // Adiciona no início para o mais recente aparecer no topo
      VehicleLog(
        agentName: agentName,
        actionType: actionType,
        timestamp: DateTime.now(),
        observations: observations,
        placa: placa,
        modelo: modelo,
        quilometragem: quilometragem,
      ),
    );
    notifyListeners();
  }

  /// Carrega os logs do banco de dados via API
  Future<void> carregarMovimentacoes({String? agente}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final dados = await ApiService.listarMovimentacoes(agente: agente);

      _logs.clear();
      for (var item in dados) {
        _logs.add(VehicleLog.fromJson(item as Map<String, dynamic>));
      }
    } catch (e) {
      print('Erro ao carregar movimentações do banco: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}
