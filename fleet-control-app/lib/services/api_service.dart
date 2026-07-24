import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:3000/api';

  // 1. Buscar o veículo pela placa cadastrada
  static Future<Map<String, dynamic>> buscarVeiculoPorPlaca(String placa) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/viaturas/$placa'));

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
      final response = await http.get(Uri.parse('$baseUrl/viaturas'));
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

  // 3. Cadastrar nova viatura
  static Future<bool> cadastrarViatura(Map<String, dynamic> dadosViatura) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/viaturas'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(dadosViatura),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Erro ao cadastrar viatura: $e');
      return false;
    }
  }

  // 3.1. Atualizar dados ou status da viatura existente
  static Future<bool> atualizarViatura(int id, Map<String, dynamic> dadosViatura) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/viaturas/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(dadosViatura),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Erro ao atualizar viatura: $e');
      return false;
    }
  }

  // 4. Excluir viatura
  static Future<bool> excluirViatura(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/viaturas/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao excluir viatura: $e');
      return false;
    }
  }

  // 5. Registrar movimentação oficial (Saída/Entrada)
  static Future<bool> registrarMovimentacao(Map<String, dynamic> dadosMovimento) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/movimentacoes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(dadosMovimento),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Movimentação salva com sucesso!');
        return true;
      } else {
        print('Erro ao salvar movimentação: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Erro de conexão na movimentação: $e');
      return false;
    }
  }

  // 6. Verificar se a viatura possui uma saída pendente (para validar a Devolução)
  // CORRIGIDO: o backend retorna { encontrada: true/false } com status 200,
  // então verificamos o campo booleano em vez de testar null.
  static Future<Map<String, dynamic>?> verificarSaidaAtiva(String placa) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/movimentacoes/saida-ativa/$placa'));

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

  // 7. Verificar se o usuário já possui alguma viatura em uso (impedir 2 retiradas)
  // CORRIGIDO: o backend retorna { ativo: true/false } com status 200,
  // então verificamos o campo booleano em vez de testar null.
  static Future<Map<String, dynamic>?> verificarUsuarioComSaidaAtiva(String nomeAgente) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/movimentacoes/usuario-ativo/$nomeAgente'));

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
      final response = await http.get(uri);

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

  // 9. Registrar infrações enviando para o Node.js
  static Future<bool> registrarInfracao({
    required String numeroAuto,
    required String placaViatura,
    required String local,
    required String dataHora,
    required String agenteResponsavel,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/infracoes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'numero_auto': numeroAuto,
          'placa_viatura': placaViatura,
          'local': local,
          'data_hora': dataHora,
          'agente_responsavel': agenteResponsavel,
        }),
      );

      if (response.statusCode == 201) {
        print('Infração salva com sucesso!');
        return true;
      } else {
        print('Erro ao salvar: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Erro de conexão com a API: $e');
      return false;
    }
  }
}
