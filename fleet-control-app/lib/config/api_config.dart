/// Configuração centralizada de URLs da API.
///
/// Para alternar entre ambiente local e produção, basta mudar o valor de [useProduction].
///
/// - Ambiente local: servidor backend rodando em http://localhost:3000
/// - Ambiente de produção: servidor em https://analise.policiacivil.pe.gov.br
class ApiConfig {
  /// Define se as requisições usam o ambiente de produção.
  /// Altere para `false` para usar o backend local durante desenvolvimento/testes.
  static const bool useProduction = false;

  // ---------------------------------------------------------------------------
  // URLs base
  // ---------------------------------------------------------------------------

  /// URL base do servidor backend (gestão de viaturas, movimentações, etc.).
  static const String _localBaseUrl = 'http://localhost:3000/api';
  static const String _productionBaseUrl =
      'https://analise.policiacivil.pe.gov.br/api';

  /// URL base da API atualmente ativa.
  static String get baseUrl =>
      useProduction ? _productionBaseUrl : _localBaseUrl;

  // ---------------------------------------------------------------------------
  // Webhook de login (autenticação externa)
  // ---------------------------------------------------------------------------

  /// URL do webhook de login — ambiente local (usa a mesma rota externa de produção).
  static const String _localLoginUrl =
      'https://analise.policiacivil.pe.gov.br/webhook/loginSgv';

  /// URL do webhook de login — ambiente de produção.
  static const String _productionLoginUrl =
      'https://analise.policiacivil.pe.gov.br/webhook/loginSgv';

  /// URL do webhook de login atualmente ativa.
  static String get loginUrl =>
      useProduction ? _productionLoginUrl : _localLoginUrl;

  /// Token de autorização para o webhook de login.
  static const String loginToken =
      'token_AdbpGk1GaEUAb93B5ueSfCo7ZzPsXNJw';
}