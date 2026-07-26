import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  // 0. Buscar o último KM registrado para uma viatura
  static Future<int?> buscarUltimoKm(String placa) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/viaturas/${Uri.encodeComponent(placa)}/ultimo-km'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ultimo_km'] as int?;
      }
      return null;
    } catch (e) {
      print('Erro ao buscar último KM: $e');
      return null;
    }
  }

  // 1. Buscar o veículo pela placa cadastrada
  static Future<Map<String, dynamic>> buscarVeiculoPorPlaca(String placa) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/viaturas/$placa'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Veículo não encontrado');
      }
    } catch (e) {
      print('Erro ao buscar veículo: $e');
      rethrow;
    }
  }

  // 2. Listar todas as viaturas cadastradas (Gestão de Frotas)
  static Future<List<dynamic>> listarTodasViaturas() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/viaturas'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return [];
      }
    } catch (e) {
      print('Erro ao listar viaturas: $e');
      return [];
    }
  }

  // 3. Cadastrar nova viatura (agora com quilometragem_inicial)
  static Future<bool> cadastrarViatura(Map<String, dynamic> dadosViatura) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/viaturas'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dadosViatura),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Erro ao cadastrar viatura: $e');
      return false;
    }
  }

  // 3.1. Atualizar dados ou status da viatura existente
  static Future<bool> atualizarViatura(int id, Map<String, dynamic> dadosViatura) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/viaturas/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dadosViatura),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Erro ao atualizar viatura: $e');
      return false;
    }
  }

  // 4. Excluir viatura
  static Future<bool> excluirViatura(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/viaturas/$id'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao excluir viatura: $e');
      return false;
    }
  }

  // 5. Registrar movimentação oficial (Saída/Devolução)
  static Future<bool> registrarMovimentacao(Map<String, dynamic> dadosMovimento) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/movimentacoes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dadosMovimento),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Movimentação salva com sucesso!');
        return true;
      } else if (response.statusCode == 409) {
        final data = jsonDecode(response.body);
        throw Exception(data['mensagem'] ?? 'Operação bloqueada por regra de negócio.');
      } else {
        print('Erro ao salvar movimentação: ${response.body}');
        return false;
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Operação bloqueada')) {
        rethrow;
      }
      print('Erro de conexão na movimentação: $e');
      return false;
    }
  }

  // 6. Verificar se a viatura possui uma saída pendente (para validar a Devolução)
  static Future<Map<String, dynamic>?> verificarSaidaAtiva(String placa) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/movimentacoes/saida-ativa/$placa'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['encontrada'] == true) {
          return data;
        }
        return null;
      } else {
        return null;
      }
    } catch (e) {
      print('Erro ao verificar saída ativa: $e');
      return null;
    }
  }

  // 7. Verificar se o usuário já possui alguma viatura em uso
  static Future<Map<String, dynamic>?> verificarUsuarioComSaidaAtiva(String nomeAgente) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/movimentacoes/usuario-ativo/$nomeAgente'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ativo'] == true) {
          return data;
        }
        return null;
      } else {
        return null;
      }
    } catch (e) {
      print('Erro ao verificar usuário com saída ativa: $e');
      return null;
    }
  }

  // 8. Buscar histórico de movimentações (permite filtro opcional por agente)
  static Future<List<dynamic>> listarMovimentacoes({String? agente}) async {
    try {
      final uri = agente != null
          ? Uri.parse('$baseUrl/movimentacoes?agente=${Uri.encodeComponent(agente)}')
          : Uri.parse('$baseUrl/movimentacoes');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return [];
      }
    } catch (e) {
      print('Erro ao listar movimentações: $e');
      return [];
    }
  }

  // 10. Buscar ou criar usuário no banco local (retorna cargo real)
  static Future<Map<String, dynamic>?> buscarOuCriarUsuario({
    required String cpf,
    required String nome,
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/usuarios/buscar-ou-criar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'cpf': cpf,
              'nome': nome,
              'email': email,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Erro ao buscar/criar usuário: $e');
      return null;
    }
  }

  // 9. Processar e vincular infração (cruzamento inteligente)
  static Future<Map<String, dynamic>> processarInfracao({
    required String numeroAuto,
    required String placaViatura,
    required String local,
    required String dataHora,
    String? agenteResponsavel,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/infracoes/processar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'numero_auto': numeroAuto,
              'placa_viatura': placaViatura,
              'local': local,
              'data_hora': dataHora,
              'agente_responsavel': agenteResponsavel ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return decoded;
      } else {
        throw Exception(decoded['erro'] ?? 'Erro ao processar infração');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro de conexão com a API: $e');
    }
  }

  // 9c. Buscar infrações por placa da viatura
  static Future<List<dynamic>> buscarInfracoesPorPlaca(String placa) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/infracoes/busca/${Uri.encodeComponent(placa)}'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      print('Erro ao buscar infrações por placa: $e');
      return [];
    }
  }

  // 9b. Método legado (compatibilidade)
  static Future<bool> registrarInfracao({
    required String numeroAuto,
    required String placaViatura,
    required String local,
    required String dataHora,
    required String agenteResponsavel,
  }) async {
    try {
      await processarInfracao(
        numeroAuto: numeroAuto,
        placaViatura: placaViatura,
        local: local,
        dataHora: dataHora,
        agenteResponsavel: agenteResponsavel,
      );
      return true;
    } catch (e) {
      print('Erro ao registrar infração: $e');
      return false;
    }
  }

  // ==========================================
  // ENDPOINTS DE MANUTENÇÃO
  // ==========================================

  // 11. Verificar alertas de manutenção para uma viatura
  static Future<List<dynamic>> verificarAlertasManutencao(String placa) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/manutencoes/alertas/$placa'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alertas'] ?? [];
      }
      return [];
    } catch (e) {
      print('Erro ao verificar alertas de manutenção: $e');
      return [];
    }
  }

  // 12. Listar todas as manutenções pendentes (painel de manutenção)
  static Future<List<dynamic>> listarManutencoesPendentes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/manutencoes'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Erro ao listar manutenções: $e');
      return [];
    }
  }

  // ==========================================
  // ENDPOINTS DE GESTÃO DE USUÁRIOS ADMINISTRADORES
  // ==========================================

  // 14. Listar todos os usuários cadastrados no banco
  static Future<List<dynamic>> listarUsuarios() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/usuarios'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Erro ao listar usuários: $e');
      return [];
    }
  }

  // 15. Cadastrar novo usuário administrador
  static Future<Map<String, dynamic>> cadastrarAdmin({
    required String cpf,
    required String nome,
    required String email,
    required String cargo,
    required String senha,
    required String adminSolicitanteCpf,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/usuarios/cadastrar-admin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'cpf': cpf,
              'nome': nome,
              'email': email,
              'cargo': cargo,
              'senha': senha,
              'admin_solicitante_cpf': adminSolicitanteCpf,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'sucesso': true, 'mensagem': decoded['mensagem'], 'usuario': decoded['usuario']};
      } else {
        return {'sucesso': false, 'mensagem': decoded['erro'] ?? 'Erro ao cadastrar administrador.'};
      }
    } catch (e) {
      print('Erro ao cadastrar administrador: $e');
      return {'sucesso': false, 'mensagem': 'Erro de conexão ao cadastrar administrador.'};
    }
  }

  // 13. Dar baixa em manutenção (total ou parcial)
  static Future<bool> baixarManutencao({
    required String placa,
    String? componente,
    bool baixarTodas = false,
    required String baixadoPor,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/manutencoes/1/baixa'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'placa': placa,
              'componente': componente,
              'baixar_todas': baixarTodas,
              'baixado_por': baixadoPor,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao dar baixa em manutenção: $e');
      return false;
    }
  }
  // ==========================================
  // NOVOS ENDPOINTS – NOTIFICAÇÕES, SERVIÇOS, MEUS DADOS
  // ==========================================

  // 14. Buscar notificações do usuário por CPF
  static Future<List<dynamic>> buscarNotificacoes(String cpf) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/notificacoes/$cpf'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      print('Erro ao buscar notificações: $e');
      return [];
    }
  }

  // 14b. Buscar TODAS as notificações (ADM) com filtros opcionais
  static Future<List<dynamic>> buscarTodasNotificacoes({
    String? tipo,
    String? nome,
    String? dataInicio,
    String? dataFim,
  }) async {
    try {
      final params = <String, String>{};
      if (tipo != null && tipo.isNotEmpty) params['tipo'] = tipo;
      if (nome != null && nome.isNotEmpty) params['nome'] = nome;
      if (dataInicio != null && dataInicio.isNotEmpty) params['data_inicio'] = dataInicio;
      if (dataFim != null && dataFim.isNotEmpty) params['data_fim'] = dataFim;

      final uri = Uri.parse('$baseUrl/admin/notificacoes').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      print('Erro ao buscar todas notificações: $e');
      return [];
    }
  }

  // 15. Marcar notificação como lida
  static Future<bool> marcarNotificacaoLida(int id) async {
    try {
      final response = await http
          .put(Uri.parse('$baseUrl/notificacoes/$id/lida'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao marcar notificação: $e');
      return false;
    }
  }

  // 16. Criar solicitação de manutenção / chamado de avaria
  static Future<Map<String, dynamic>?> criarSolicitacaoManutencao({
    required String placa,
    required String agenteNome,
    required String cpfAgente,
    required String tipoProblema,
    required String descricao,
    int? kmAtual,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/solicitacoes-manutencao'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'placa': placa,
              'agente_nome': agenteNome,
              'cpf_agente': cpfAgente,
              'tipo_problema': tipoProblema,
              'descricao': descricao,
              'km_atual': kmAtual,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 201) return jsonDecode(response.body);
      return null;
    } catch (e) {
      print('Erro ao criar solicitação: $e');
      return null;
    }
  }

  // 17. Buscar solicitações de manutenção do agente
  static Future<List<dynamic>> buscarSolicitacoesManutencao(String cpf) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/solicitacoes-manutencao/$cpf'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      print('Erro ao buscar solicitações: $e');
      return [];
    }
  }

  // 18. Criar checklist de inspeção diária
  static Future<Map<String, dynamic>?> criarChecklist(Map<String, dynamic> dados) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/checklists'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dados),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 201) return jsonDecode(response.body);
      return null;
    } catch (e) {
      print('Erro ao criar checklist: $e');
      return null;
    }
  }

  // 19. Buscar checklists do agente
  static Future<List<dynamic>> buscarChecklists(String cpf) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/checklists/$cpf'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      print('Erro ao buscar checklists: $e');
      return [];
    }
  }

  // 20. Buscar detalhes completos do usuário (Meus Dados)
  static Future<Map<String, dynamic>?> buscarDetalhesUsuario(String cpf) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/usuarios/detalhes/$cpf'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      print('Erro ao buscar detalhes do usuário: $e');
      return null;
    }
  }
}
