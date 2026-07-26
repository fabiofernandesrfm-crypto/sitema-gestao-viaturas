import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main_screen.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  String get _apiUrl => ApiConfig.loginUrl;
  String get _tokenLogin => ApiConfig.loginToken;

  Future<void> _handleLogin() async {
    final user = _userController.text.trim();
    final pass = _passwordController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha o usuário e a senha.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final Map<String, dynamic> payload = {
      "login": user.toLowerCase(),
      "pass": pass,
      "orgao": "policiacivil",
      "ip": "136.135.135",
    };

    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              "Authorization": _tokenLogin,
              "Content-Type": "application/json",
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      print('STATUS CODE: ${response.statusCode}');
      print('BODY DA RESPOSTA: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          print('JSON DECODIFICADO COM SUCESSO: $responseData');
          
          final acesso = responseData['acesso']?.toString().toLowerCase() ?? '';
          
          if (acesso == 'permitido') {
            print('ACESSO PERMITIDO! Iniciando mapeamento dinâmico...');
            if (!mounted) return;
            
            final agora = DateTime.now();
            final horaFormatada = 
                '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} ${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
            
            // Dados do webhook (login externo) — usados como fallback
            final nomeUsuario = responseData['nome'] ?? '';
            final emailUsuario = responseData['email'] ?? '';
            // Remove formatação: pontos, traços e barras do CPF
            final cpfUsuario = (responseData['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');

            // ================================================================
            // MAPEAMENTO DINÂMICO DE PERFIL
            // ================================================================
            // O webhook externo apenas AUTENTICA o usuário.
            // A AUTORIZAÇÃO (cargo e perfil administrador) é determinada
            // pelo banco de dados LOCAL (PostgreSQL), garantindo que:
            //   - fabiofernandes SEMPRE retorne como Agente (is_adm = false)
            //   - Apenas o Delegado Titular tenha acesso administrativo
            // ================================================================
            bool isAdm = false;
            String cargoFinal = 'Agente';

            if (cpfUsuario.isNotEmpty) {
              try {
                final usuarioLocal = await ApiService.buscarOuCriarUsuario(
                  cpf: cpfUsuario,
                  nome: nomeUsuario,
                  email: emailUsuario,
                );
                if (usuarioLocal != null) {
                  isAdm = usuarioLocal['is_adm'] == true;
                  cargoFinal = (usuarioLocal['cargo']?.toString().trim() ?? '');
                  if (cargoFinal.isEmpty) cargoFinal = 'Agente';
                  print('MAPEAMENTO DINÂMICO [OK]: Banco local -> cargo=$cargoFinal | isAdm=$isAdm | cpf=$cpfUsuario');
                } else {
                  print('MAPEAMENTO DINÂMICO [FALHA]: API local retornou null. Usando fallback do webhook.');
                  // Fallback para dados do webhook
                  final admRaw = responseData['adm'] ?? responseData['isAdm'] ?? false;
                  if (admRaw is bool) {
                    isAdm = admRaw;
                  } else {
                    final valStr = admRaw.toString().toLowerCase();
                    isAdm = (valStr == 'true' || valStr == 's' || valStr == 'sim' || valStr == '1');
                  }
                  cargoFinal = (responseData['cargo'] ?? responseData['funcao'] ?? 'Agente').toString().trim();
                  if (cargoFinal.isEmpty) cargoFinal = 'Agente';
                }
              } catch (e) {
                print('MAPEAMENTO DINÂMICO [ERRO]: Exceção ao consultar API local — $e');
                // Fallback: usa valores do webhook como último recurso
                final admRaw = responseData['adm'] ?? responseData['isAdm'] ?? false;
                if (admRaw is bool) {
                  isAdm = admRaw;
                } else {
                  final valStr = admRaw.toString().toLowerCase();
                  isAdm = (valStr == 'true' || valStr == 's' || valStr == 'sim' || valStr == '1');
                }
                cargoFinal = (responseData['cargo'] ?? responseData['funcao'] ?? 'Agente').toString().trim();
                if (cargoFinal.isEmpty) cargoFinal = 'Agente';
              }
            } else {
              print('MAPEAMENTO DINÂMICO [AVISO]: CPF vazio. Webhook não retornou CPF. Usando dados do webhook.');
              final admRaw = responseData['adm'] ?? false;
              isAdm = admRaw is bool ? admRaw : admRaw.toString().toLowerCase() == 'true';
              cargoFinal = (responseData['cargo'] ?? 'Agente').toString().trim();
              if (cargoFinal.isEmpty) cargoFinal = 'Agente';
            }

            // Salva a sessão e os dados do usuário
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isLoggedIn', true);
            await prefs.setInt('loginTimestamp', agora.millisecondsSinceEpoch);

            await prefs.setString('nome', nomeUsuario);
            await prefs.setString('cpf', cpfUsuario);
            await prefs.setString('email', emailUsuario);
            await prefs.setString('cargo', cargoFinal);
            await prefs.setBool('isAdm', isAdm);
            await prefs.setInt('horaLoginTimestamp', agora.millisecondsSinceEpoch);

            print('LOGIN CONCLUÍDO: $nomeUsuario | cargo=$cargoFinal | isAdm=$isAdm');
            
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MainScreen(
                  nome: nomeUsuario,
                  cargo: cargoFinal,
                  isAdm: isAdm,
                  cpf: cpfUsuario,
                  email: emailUsuario,
                  horaLogin: horaFormatada,
                ),
              ),
            );
            return;
          } else {
            print('O campo acesso veio com valor diferente: $acesso');
          }
        } catch (e) {
          print('ERRO EXATO NO CATCH DO JSON: $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário ou senha inválidos!'),
          backgroundColor: Colors.red,
        ),
      );

    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tempo de conexão esgotado. Verifique se o servidor está rodando.'),
          backgroundColor: Colors.red,
        ),
      );
    } on http.ClientException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível conectar ao servidor. Verifique sua rede.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro de conexão: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_police,
                    size: 48,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SGV',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sistema de Gestão de Viaturas\nPolícia Civil de Pernambuco',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _userController,
                  decoration: InputDecoration(
                    labelText: 'Usuário',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Entrar',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Controle Operacional de Viaturas',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'PREVENIR, APURAR E REPRIMIR!',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}