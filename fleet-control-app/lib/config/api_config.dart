/// Configuração centralizada de URLs da API.
///
/// Suporta três modos de operação:
/// 1. Desenvolvimento local: backend em http://localhost:3000
/// 2. Produção (domínio próprio): definido via --dart-define=API_BASE_URL=<url>
/// 3. Produção (mesma origem): nginx faz proxy reverso, use API_BASE_URL=/api
///
/// Para build de produção com Easypanel:
///   flutter build web --dart-define=API_BASE_URL=https://seu-dominio.com/api
///
/// Ou para mesma origem (recomendado com nginx reverse proxy):
///   flutter build web --dart-define=API_BASE_URL=/api
class ApiConfig {
  // ---------------------------------------------------------------------------
  // URLs base
  // ---------------------------------------------------------------------------

  /// URL base do servidor backend.
  /// Em desenvolvimento local: http://localhost:3000/api
  /// Em produção: definida via --dart-define=API_BASE_URL ou usa produção fixa.
  static const String _localBaseUrl = 'http://localhost:3000/api';
  static const String _productionBaseUrl =
      'https://analise.policiacivil.pe.gov.br/api';

  /// URL base da API atualmente ativa.
  /// Prioridade: 1) dart-define  2) useProduction ? produção : local
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    return _localBaseUrl;
  }

  // ---------------------------------------------------------------------------
  // Webhook de login (autenticação externa)
  // ---------------------------------------------------------------------------

  /// URL do webhook de login — sempre aponta para o servidor externo de autenticação.
  static const String loginUrl =
      'https://analise.policiacivil.pe.gov.br/webhook/loginSgv';

  /// Token de autorização para o webhook de login.
  static const String loginToken =
      'token_AdbpGk1GaEUAb93B5ueSfCo7ZzPsXNJw';
}