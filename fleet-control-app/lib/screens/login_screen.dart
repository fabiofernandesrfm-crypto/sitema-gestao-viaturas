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
            bool isMaster = false;
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
                  isMaster = usuarioLocal['is_master'] == true;
                  cargoFinal = (usuarioLocal['cargo']?.toString().trim() ?? '');
                  if (cargoFinal.isEmpty) cargoFinal = 'Agente';
                  print('MAPEAMENTO DINÂMICO [OK]: Banco local -> cargo=$cargoFinal | isAdm=$isAdm | isMaster=$isMaster | cpf=$cpfUsuario');
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
            await prefs.setBool('isMaster', isMaster);
            await prefs.setInt('horaLoginTimestamp', agora.millisecondsSinceEpoch);

            print('LOGIN CONCLUÍDO: $nomeUsuario | cargo=$cargoFinal | isAdm=$isAdm | isMaster=$isMaster');
            
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MainScreen(
                  nome: nomeUsuario,
                  cargo: cargoFinal,
                  isAdm: isAdm,
                  isMaster: isMaster,
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0F1E),
              Color(0xFF111B33),
              Color(0xFF0D1527),
              Color(0xFF060B17),
            ],
            stops: [0.0, 0.35, 0.70, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Subtle radial glow behind the card
            Center(
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF1E3A8A).withOpacity(0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            // Decorative top bar accent
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1E3A8A),
                      Color(0xFF3B82F6),
                      Color(0xFF1E3A8A),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDFDFD),
                    borderRadius: BorderRadius.circular(20.0),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A8A).withOpacity(0.25),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shield icon in an elevated container
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF0F172A),
                              Color(0xFF1E293B),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_police,
                          size: 42,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // SGV title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                        ).createShader(bounds),
                        child: const Text(
                          'SGV',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Divider line
                      Container(
                        width: 48,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Sistema de Gestão de Viaturas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Polícia Civil de Pernambuco',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 36),
                      // Username field
                      TextField(
                        controller: _userController,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Usuário',
                          labelStyle: const TextStyle(color: Color(0xFF64748B)),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14.0),
                            child: Icon(Icons.person_outline, color: Color(0xFF64748B), size: 22),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Password field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          labelStyle: const TextStyle(color: Color(0xFF64748B)),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14.0),
                            child: Icon(Icons.lock_outline, color: Color(0xFF64748B), size: 22),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF94A3B8),
                              size: 22,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Login button
                      Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.transparent,
                            disabledForegroundColor: Colors.white54,
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Entrar',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Bottom motto box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'Controle Operacional de Viaturas',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E3A8A),
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'PREVENIR, APURAR E REPRIMIR!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}