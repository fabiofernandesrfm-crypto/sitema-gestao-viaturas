import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../models/vehicle_log.dart';
import '../providers/log_provider.dart';
import '../services/api_service.dart';
import '../services/ocr_service.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  final String nome;
  final String cargo;
  final bool isAdm;
  final bool isMaster;
  final String cpf;
  final String email;
  final String horaLogin;

  const MainScreen({
    Key? key,
    required this.nome,
    required this.cargo,
    required this.isAdm,
    required this.isMaster,
    required this.cpf,
    required this.email,
    required this.horaLogin,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  String get nome => widget.nome;
  String get cargo => widget.cargo;
  bool get isAdm => widget.isAdm;
  bool get isMaster => widget.isMaster;
  String get cpf => widget.cpf;
  String get email => widget.email;
  String get horaLogin => widget.horaLogin;

  void _showModuleScreen(BuildContext context, String moduleName, bool hasPhotoFeature) {
    final TextEditingController placaController = TextEditingController();
    final TextEditingController kmController = TextEditingController();
    final OcrService _ocrService = OcrService();

    String placaIdentificada = '';
    String modeloIdentificado = '';
    String corIdentificada = '';
    String kmIdentificado = '';
    String dadosTratados = '';

    bool fotoPlacaTirada = false;
    bool fotoPainelTirada = false;
    bool isLoadingPlaca = false;
    bool isLoadingKm = false;
    bool salvando = false;
    int kmMinimoSaida = 0;

    bool dadosValidos() {
      final placaOk = placaIdentificada.isNotEmpty && placaIdentificada.length >= 4;
      final kmOk = kmIdentificado.isNotEmpty &&
          int.tryParse(kmIdentificado.replaceAll(RegExp(r'[^0-9]'), '')) != null;
      return placaOk && kmOk;
    }

    /// Valida se o KM informado é >= ao KM mínimo exigido (regra de negócio)
    String? validarKmMinimo() {
      if (kmMinimoSaida <= 0) return null; // sem referência para comparar
      final kmNumerico = int.tryParse(kmIdentificado.replaceAll(RegExp(r'[^0-9]'), ''));
      if (kmNumerico == null) return null;
      if (kmNumerico < kmMinimoSaida) {
        if (moduleName == 'Saída de Viatura') {
          return 'KM informado ($kmNumerico) é menor que o KM inicial de cadastro ($kmMinimoSaida).';
        } else {
          return 'KM informado ($kmNumerico) é menor que o KM da saída ($kmMinimoSaida).';
        }
      }
      return null;
    }

    void atualizarPainelDadosTratados(StateSetter setStateModal) {
      final now = DateTime.now();
      final dataHora =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      List<String> partes = [];
      if (placaIdentificada.isNotEmpty) {
        partes.add('🚗 Placa: $placaIdentificada');
        if (modeloIdentificado.isNotEmpty) {
          partes.add('Modelo: $modeloIdentificado ($corIdentificada)');
        }
      }
      if (kmIdentificado.isNotEmpty) {
        partes.add('🔢 KM: $kmIdentificado');
      }
      partes.add('📅 $dataHora');

      dadosTratados = partes.join('\n');
      setStateModal(() {});
    }

    Future<void> processarPlaca(String placaBruta, StateSetter setStateModal) async {
      if (placaBruta.trim().isEmpty) return;

      setStateModal(() => isLoadingPlaca = true);

      final placaLimpa = placaBruta.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

      if (moduleName == 'Saída de Viatura') {
        final saidaAtiva = await ApiService.verificarSaidaAtiva(placaLimpa);
        if (saidaAtiva != null) {
          setStateModal(() => isLoadingPlaca = false);
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Saída Bloqueada'),
              content: Text(
                  'A viatura de placa $placaLimpa já se encontra em uso/fora da base. Não é possível gerar uma nova saída.'),
              actions: [
                ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
              ],
            ),
          );
          return;
        }
      }

      if (moduleName == 'Devolução de Viatura') {
        final saidaAtiva = await ApiService.verificarSaidaAtiva(placaLimpa);
        if (saidaAtiva == null) {
          setStateModal(() => isLoadingPlaca = false);
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Devolução Bloqueada'),
              content: Text(
                  'A viatura de placa $placaLimpa não possui registro de saída ativo. Não é possível realizar a devolução.'),
              actions: [
                ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
              ],
            ),
          );
          return;
        }

        // Captura o KM da saída para validação na devolução
        final dadosSaida = saidaAtiva['dados'];
        if (dadosSaida != null && dadosSaida is Map && dadosSaida['quilometragem'] != null) {
          final dynamic kmSaida = dadosSaida['quilometragem'];
          kmMinimoSaida = kmSaida is int ? kmSaida : (int.tryParse(kmSaida.toString()) ?? 0);
        }
      }

      try {
        final veiculo = await ApiService.buscarVeiculoPorPlaca(placaLimpa);
        fotoPlacaTirada = true;
        placaIdentificada = veiculo['placa'] ?? placaLimpa;
        modeloIdentificado = veiculo['modelo'] ?? 'Modelo não informado';
        corIdentificada = veiculo['cor'] ?? 'Cor não informada';
        // Para Saída, define o KM mínimo como o KM inicial do cadastro
        if (moduleName == 'Saída de Viatura') {
          kmMinimoSaida = int.tryParse((veiculo['quilometragem_inicial'] ?? 0).toString()) ?? 0;

          // Preenchimento automático do KM: busca último registro ou usa KM inicial
          final ultimoKm = await ApiService.buscarUltimoKm(placaLimpa);
          final kmDefinitivo = (ultimoKm != null && ultimoKm > 0) ? ultimoKm : kmMinimoSaida;
          if (kmDefinitivo > 0) {
            kmController.text = kmDefinitivo.toString();
            kmIdentificado = kmDefinitivo.toString();
            fotoPainelTirada = true;
            // Força atualização imediata dos dados tratados e do status
            atualizarPainelDadosTratados(setStateModal);
          }
        }
      } catch (e) {
        fotoPlacaTirada = true;
        placaIdentificada = placaLimpa;
        modeloIdentificado = 'Veículo não cadastrado';
        corIdentificada = '-';
      }

      placaController.text = placaIdentificada;
      isLoadingPlaca = false;
      atualizarPainelDadosTratados(setStateModal);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Placa identificada: $placaIdentificada'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    void _onKmPreenchido(BuildContext context, String km, StateSetter setStateModal) {
      kmIdentificado = km;
      if (km.isNotEmpty) {
        fotoPainelTirada = true;
      } else {
        fotoPainelTirada = false;
      }
      atualizarPainelDadosTratados(setStateModal);

    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Row(
            children: [
              Icon(
                moduleName == 'Devolução de Viatura' ? Icons.login : Icons.exit_to_app,
                color: moduleName == 'Devolução de Viatura'
                    ? Colors.green.shade800
                    : Colors.blue.shade800,
              ),
              const SizedBox(width: 8),
              Text(moduleName),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasPhotoFeature) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📷 Captura de Evidências',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isLoadingPlaca
                                      ? null
                                      : () async {
                                          String? placaExtraida =
                                              await _ocrService.lerPlacaDaCamera();
                                          if (placaExtraida != null) {
                                            await processarPlaca(placaExtraida, setStateModal);
                                          }
                                        },
                                  icon: isLoadingPlaca
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(Icons.camera_alt,
                                          color: fotoPlacaTirada ? Colors.green : null),
                                  label: Text(
                                    fotoPlacaTirada ? 'Placa OK ✓' : 'Foto Placa',
                                    style: TextStyle(
                                      color: fotoPlacaTirada ? Colors.green : null,
                                      fontWeight: fotoPlacaTirada
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                        color: fotoPlacaTirada ? Colors.green : Colors.grey),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 12),
                                  ),
                                ),
                              ),
                              // Foto Painel: apenas para Devolução (Saída usa KM automático)
                              if (moduleName != 'Saída de Viatura')
                                ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isLoadingKm
                                          ? null
                                          : () async {
                                              setStateModal(() => isLoadingKm = true);
                                              String? kmExtraido =
                                                  await _ocrService.lerKmDoPainel();
                                              setStateModal(() => isLoadingKm = false);

                                              if (kmExtraido != null) {
                                                final kmLimpo = kmExtraido
                                                    .replaceAll(RegExp(r'[^0-9]'), '');
                                                kmController.text = kmLimpo;
                                                _onKmPreenchido(context, kmLimpo, setStateModal);

                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('KM lido: $kmLimpo'),
                                                      backgroundColor: Colors.blue,
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      icon: isLoadingKm
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2))
                                          : Icon(Icons.photo_camera,
                                              color: fotoPainelTirada ? Colors.green : null),
                                      label: Text(
                                        fotoPainelTirada ? 'Painel OK ✓' : 'Foto Painel',
                                        style: TextStyle(
                                          color: fotoPainelTirada ? Colors.green : null,
                                          fontWeight: fotoPainelTirada
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 12,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color: fotoPainelTirada ? Colors.green : Colors.grey),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('✏️ Dados Manuais (Preenchimento ou Correção)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 10),
                        _buildPlacaAutocomplete(
                          controller: placaController,
                          onPlacaSelecionada: (placa) {
                            processarPlaca(placa, setStateModal);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: kmController,
                          readOnly: moduleName == 'Saída de Viatura',
                          decoration: InputDecoration(
                            labelText: moduleName == 'Saída de Viatura'
                                ? 'Quilometragem (KM) — Automático'
                                : 'Quilometragem (KM)',
                            hintText: moduleName == 'Saída de Viatura'
                                ? 'Preenchido automaticamente'
                                : 'Ex: 12345',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.speed),
                            suffixIcon: fotoPainelTirada
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            filled: moduleName == 'Saída de Viatura',
                            fillColor: moduleName == 'Saída de Viatura'
                                ? Colors.grey.shade100
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: moduleName == 'Saída de Viatura'
                              ? null
                              : (value) {
                                  _onKmPreenchido(context, value, setStateModal);
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dadosValidos() ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: dadosValidos() ? Colors.green.shade300 : Colors.grey.shade300,
                        width: dadosValidos() ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              dadosValidos() ? Icons.verified : Icons.info_outline,
                              color: dadosValidos() ? Colors.green : Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dadosValidos()
                                  ? '✅ Dados Tratados - Pronto para Salvar'
                                  : '📋 Dados Tratados',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: dadosValidos()
                                    ? Colors.green.shade800
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (dadosTratados.isNotEmpty)
                          Text(
                            dadosTratados,
                            style: TextStyle(
                              fontSize: 15,
                              color: dadosValidos()
                                  ? Colors.green.shade900
                                  : Colors.grey.shade800,
                              fontWeight: dadosValidos() ? FontWeight.w600 : FontWeight.normal,
                            ),
                          )
                        else
                          Text(
                            'Aguardando identificação da placa e quilometragem...\nUse as câmeras ou digite manualmente.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildStatusChip(
                        'Placa',
                        placaIdentificada.isNotEmpty && placaIdentificada.length >= 4,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(
                        'KM',
                        kmIdentificado.isNotEmpty &&
                            int.tryParse(
                                    kmIdentificado.replaceAll(RegExp(r'[^0-9]'), '')) !=
                                null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _ocrService.dispose();
                placaController.dispose();
                kmController.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Fechar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: dadosValidos() ? Colors.green.shade700 : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: (!dadosValidos() || salvando)
                  ? null
                  : () async {
                      // Validação de KM mínimo (regra de negócio)
                      final erroKm = validarKmMinimo();
                      if (erroKm != null) {
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                                  SizedBox(width: 8),
                                  Text('KM Inválido'),
                                ],
                              ),
                              content: Text(erroKm),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(_),
                                  child: const Text('Corrigir'),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }

                      // Verifica alertas de manutenção apenas na Saída de Viatura
                      List<dynamic> alertasManutencao = [];
                      if (moduleName == 'Saída de Viatura') {
                        try {
                          alertasManutencao = await ApiService.verificarAlertasManutencao(placaIdentificada);
                        } catch (_) {}
                        if (alertasManutencao.isNotEmpty && context.mounted) {
                          await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                                  SizedBox(width: 8),
                                  Text('Aviso de Manutenção'),
                                ],
                              ),
                              content: SizedBox(
                                width: 450,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'A viatura $placaIdentificada possui os seguintes itens de manutenção pendentes:',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 12),
                                    ...alertasManutencao.map((a) => Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.build, color: Colors.red, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${a['componente']} (Limite: ${a['km_limite']} km)',
                                                  style: const TextStyle(fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.info_outline, color: Colors.blue, size: 18),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Este é apenas um aviso informativo. A operação não será bloqueada.',
                                              style: TextStyle(fontSize: 12, color: Colors.blue),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Entendi'),
                                ),
                              ],
                            ),
                          );
                        }
                      }

                      setStateModal(() => salvando = true);

                      final kmNumerico =
                          int.tryParse(kmIdentificado.replaceAll(RegExp(r'[^0-9]'), ''));

                      Provider.of<LogProvider>(context, listen: false).addLog(
                        agentName: nome,
                        actionType: moduleName,
                        observations: dadosTratados,
                        placa: placaIdentificada,
                        modelo: modeloIdentificado.isNotEmpty
                            ? '$modeloIdentificado ($corIdentificada)'
                            : '',
                        quilometragem: kmNumerico,
                      );

                      try {
                        final response = await ApiService.registrarMovimentacao({
                          'agente_nome': nome,
                          'tipo_movimento': moduleName,
                          'placa': placaIdentificada,
                          'modelo': modeloIdentificado.isNotEmpty
                              ? '$modeloIdentificado ($corIdentificada)'
                              : 'Não informado',
                          'quilometragem':
                              kmNumerico?.toString() ?? kmIdentificado,
                          'observacoes': dadosTratados,
                        });

                        _ocrService.dispose();
                        placaController.dispose();
                        kmController.dispose();

                        if (!context.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(response
                                ? 'Movimentação registrada com sucesso!'
                                : 'Erro ao salvar no servidor.'),
                            backgroundColor: response ? Colors.green : Colors.red,
                          ),
                        );
                      } catch (e) {
                        setStateModal(() => salvando = false);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro de conexão: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              icon: salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(salvando ? 'Salvando...' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool completo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: completo ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: completo ? Colors.green : Colors.grey),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completo ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: completo ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ${completo ? "OK" : "Pendente"}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: completo ? Colors.green.shade800 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ============= MODAL DE GESTÃO DE VIATURAS =============
  void _abrirModalGestaoViaturas(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    final _placaController = TextEditingController();
    final _modeloController = TextEditingController();
    final _kmInicialController = TextEditingController();

    final List<String> _listaCores = [
      'Branco',
      'Prata',
      'Preto',
      'Cinza',
      'Vermelho',
      'Azul'
    ];
    final List<String> _listaModelos = [
      'Fiat Toro',
      'Fiat Argo',
      'Fiat Strada',
      'Fiat Cronos',
      'Volkswagen Polo',
      'Renault Duster',
      'Renault Oroch',
      'Chevrolet Trailblazer',
      'Chevrolet S10',
      'Toyota Hilux',
      'Mitsubishi L200',
      'Ford Ranger'
    ];

    String? _corSelecionada;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.directions_car, color: Color(0xFF1E3A8A)),
              SizedBox(width: 8),
              Text('Cadastro de Viaturas'),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 580,
            child: Column(
              children: [
                ExpansionTile(
                  title: const Text('Cadastrar Nova Viatura',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _placaController,
                              decoration: const InputDecoration(
                                  labelText: 'Placa (Ex: ABC-1234)',
                                  border: OutlineInputBorder()),
                              validator: (v) =>
                                  v!.isEmpty ? 'Informe a placa' : null,
                            ),
                            const SizedBox(height: 8),
                            Autocomplete<String>(
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<String>.empty();
                                }
                                return _listaModelos.where((String modelo) {
                                  return modelo
                                      .toLowerCase()
                                      .contains(textEditingValue.text.toLowerCase());
                                });
                              },
                              onSelected: (String selection) {
                                _modeloController.text = selection;
                              },
                              fieldViewBuilder:
                                  (context, controller, focusNode, onEditingComplete) {
                                if (_modeloController.text.isNotEmpty &&
                                    controller.text.isEmpty) {
                                  controller.text = _modeloController.text;
                                }
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  onEditingComplete: onEditingComplete,
                                  onChanged: (val) => _modeloController.text = val,
                                  decoration: const InputDecoration(
                                    labelText: 'Modelo / Marca (Ex: Renault Duster)',
                                    border: OutlineInputBorder(),
                                    helperText:
                                        'Digite para filtrar ou ver sugestões',
                                  ),
                                  validator: (v) => _modeloController.text.isEmpty
                                      ? 'Informe o modelo'
                                      : null,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _kmInicialController,
                              decoration: const InputDecoration(
                                labelText: 'Quilometragem (KM) Inicial *',
                                hintText: 'Ex: 50000',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.speed),
                                helperText: 'KM atual da viatura no momento do cadastro',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Informe a quilometragem inicial';
                                }
                                if (int.tryParse(v) == null) {
                                  return 'Informe um valor numérico válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _corSelecionada,
                              decoration: const InputDecoration(
                                  labelText: 'Cor', border: OutlineInputBorder()),
                              hint: const Text('Selecione a cor'),
                              items: _listaCores.map((String cor) {
                                return DropdownMenuItem<String>(
                                  value: cor,
                                  child: Text(cor),
                                );
                              }).toList(),
                              validator: (v) =>
                                  v == null ? 'Selecione a cor' : null,
                              onChanged: (val) =>
                                  setStateModal(() => _corSelecionada = val),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade800),
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: const Text('Salvar Viatura',
                                  style: TextStyle(color: Colors.white)),
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  bool sucesso = await ApiService.cadastrarViatura({
                                    'placa': _placaController.text.toUpperCase(),
                                    'modelo': _modeloController.text,
                                    'cor': _corSelecionada!,
                                    'status': 'disponivel',
                                    'quilometragem_inicial': int.parse(_kmInicialController.text),
                                  });

                                  if (sucesso) {
                                    _placaController.clear();
                                    _modeloController.clear();
                                    _kmInicialController.clear();
                                    _corSelecionada = null;
                                    setStateModal(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Viatura cadastrada com sucesso!'),
                                          backgroundColor: Colors.green),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                const Text('Viaturas Cadastradas no Sistema',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: ApiService.listarTodasViaturas(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                            child: Text('Nenhuma viatura cadastrada.'));
                      }

                      final veiculos = snapshot.data!;
                      return ListView.builder(
                        itemCount: veiculos.length,
                        itemBuilder: (context, index) {
                          final v = veiculos[index];
                          bool isDisponivel =
                              (v['status'] ?? 'disponivel') == 'disponivel';
                          final kmInicial = v['quilometragem_inicial'] ?? 0;

                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.directions_car,
                                  color: isDisponivel ? Colors.green : Colors.red),
                              title: Text('${v['placa']} - ${v['modelo']}'),
                              subtitle: Text(
                                  'Cor: ${v['cor']} | Status: ${v['status']} | KM Inicial: $kmInicial'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isDisponivel
                                          ? Icons.toggle_on
                                          : Icons.toggle_off,
                                      color:
                                          isDisponivel ? Colors.green : Colors.grey,
                                      size: 30,
                                    ),
                                    tooltip: 'Alternar Status',
                                    onPressed: () async {
                                      String novoStatus = isDisponivel
                                          ? 'indisponivel'
                                          : 'disponivel';
                                      bool atualizado =
                                          await ApiService.atualizarViatura(
                                              v['id'], {
                                        'placa': v['placa'],
                                        'modelo': v['modelo'],
                                        'cor': v['cor'],
                                        'status': novoStatus,
                                      });
                                      if (atualizado) {
                                        setStateModal(() {});
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    tooltip: 'Excluir Viatura',
                                    onPressed: () async {
                                      bool deletou = await ApiService.excluirViatura(
                                          v['id']);
                                      if (deletou) {
                                        setStateModal(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  // ============= MODAL DE GESTÃO DE INFRAÇÕES (COM CRUZAMENTO INTELIGENTE) =============
  void _abrirModalInfracoes(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    final _numeroController = TextEditingController();
    final _placaController = TextEditingController();
    final _localController = TextEditingController();
    final _dataHoraController = TextEditingController();
    bool _processando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.gavel, color: Colors.orange),
              SizedBox(width: 8),
              Text('Gestão de Infrações'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cadastre os dados da infração para cruzamento automático com o histórico de viaturas:',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _numeroController,
                      decoration: const InputDecoration(
                          labelText: 'Número da Infração / Auto',
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value!.isEmpty ? 'Informe o número' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildPlacaAutocomplete(
                      controller: _placaController,
                      onPlacaSelecionada: (_) {},
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _localController,
                      decoration: const InputDecoration(
                          labelText: 'Local da Infração',
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value!.isEmpty ? 'Informe o local' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dataHoraController,
                      decoration: const InputDecoration(
                          labelText: 'Data e Hora (Ex: 23/07/2026 14:30)',
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value!.isEmpty ? 'Informe a data e hora' : null,
                    ),
                    if (_processando) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Processando cruzamento...',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                    const SizedBox(height: 16),
                    // Seção de busca por placa
                    Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🔍 Buscar Infrações por Placa:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FutureBuilder<List<String>>(
                              future: _fetchPlacasDisponiveis(),
                              builder: (context, snap) {
                                final placas = snap.data ?? [];
                                return Autocomplete<String>(
                                  optionsBuilder: (val) {
                                    if (val.text.isEmpty) return placas;
                                    return placas.where((p) => p.contains(val.text.toUpperCase()));
                                  },
                                  fieldViewBuilder: (context, ctrl, node, onDone) => TextField(
                                    controller: ctrl,
                                    focusNode: node,
                                    onEditingComplete: onDone,
                                    textCapitalization: TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'Digite a placa',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      isDense: true,
                                      prefixIcon: Icon(Icons.search, size: 18),
                                    ),
                                  ),
                                  onSelected: (placa) async {
                                    final resultados = await ApiService.buscarInfracoesPorPlaca(placa);
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      _mostrarResultadosBuscaInfracao(context, placa, resultados);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800),
              onPressed: _processando
                  ? null
                  : () async {
                      if (_formKey.currentState!.validate()) {
                        setDialogState(() => _processando = true);
                        try {
                          final resultado = await ApiService.processarInfracao(
                            numeroAuto: _numeroController.text.trim(),
                            placaViatura:
                                _placaController.text.trim().toUpperCase(),
                            local: _localController.text.trim(),
                            dataHora: _dataHoraController.text.trim(),
                            agenteResponsavel: nome,
                          );
                          setDialogState(() => _processando = false);

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);

                          if (resultado['encontrado'] == true) {
                            _mostrarResultadoInfracao(context, resultado);
                          } else {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Infração Registrada'),
                                  ],
                                ),
                                content: Text(
                                  resultado['detalhes_cruzamento'] ??
                                      'Não houve registro de quem cometeu aquela infração no período especificado.',
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(_),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => _processando = false);
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Erro: ${e.toString().replaceFirst('Exception: ', '')}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: Text(
                _processando ? 'Processando...' : 'Processar e Vincular',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarResultadoInfracao(BuildContext context, Map<String, dynamic> resultado) {
    final motorista = resultado['motorista'] as Map<String, dynamic>? ?? {};
    final infracao = resultado['infracao'] as Map<String, dynamic>? ?? {};

    final nomeMotorista = motorista['agent_name'] ?? 'Não identificado';
    final placaMotorista =
        motorista['placa'] ?? infracao['placa_viatura'] ?? '';
    final modeloMotorista = motorista['modelo'] ?? '';
    final dataSaida = motorista['data_hora_saida'] ?? '';
    final kmMotorista = motorista['quilometragem']?.toString() ?? 'N/A';
    final numAuto = infracao['numero_auto'] ?? '';
    final localInfracao = infracao['local'] ?? '';
    final dataHoraInfracao = infracao['data_hora'] ?? '';

    final mensagemWhatsApp = Uri.encodeComponent(
      '🚨 *INFRAÇÃO DE TRÂNSITO - SGV*\n\n'
      '📋 *Auto:* $numAuto\n'
      '🚗 *Placa:* $placaMotorista\n'
      '📅 *Data/Hora:* $dataHoraInfracao\n'
      '📍 *Local:* $localInfracao\n\n'
      '👤 *Responsável Identificado:* $nomeMotorista\n'
      '🔢 *KM na saída:* $kmMotorista km\n'
      '📅 *Saída registrada em:* $dataSaida\n\n'
      'Por favor, tomar as providências cabíveis.',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Infrator Identificado!'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📋 Dados da Infração',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Divider(),
                      _linhaResultado('Auto', '$numAuto'),
                      _linhaResultado('Placa', '$placaMotorista'),
                      _linhaResultado('Data/Hora', '$dataHoraInfracao'),
                      _linhaResultado('Local', '$localInfracao'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('👤 Responsável Identificado',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Divider(),
                      _linhaResultado('Nome', '$nomeMotorista'),
                      _linhaResultado('Placa da Viatura', '$placaMotorista'),
                      if (modeloMotorista.toString().isNotEmpty)
                        _linhaResultado('Modelo', '$modeloMotorista'),
                      _linhaResultado('KM na Saída', '$kmMotorista km'),
                      _linhaResultado('Data da Saída', '$dataSaida'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('📤 Encaminhar Notificação:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.mail, color: Colors.white),
                        label: const Text('E-mail',
                            style: TextStyle(color: Colors.white)),
                        onPressed: () async {
                          final subject = Uri.encodeComponent(
                              'Infração de Trânsito - Auto $numAuto');
                          final body = Uri.encodeComponent(
                            '🚨 INFRAÇÃO DE TRÂNSITO - SGV\n\n'
                            '📋 Auto: $numAuto\n'
                            '🚗 Placa: $placaMotorista\n'
                            '📅 Data/Hora: $dataHoraInfracao\n'
                            '📍 Local: $localInfracao\n\n'
                            '👤 Responsável Identificado: $nomeMotorista\n'
                            '🔢 KM na saída: $kmMotorista km\n'
                            '📅 Saída registrada em: $dataSaida\n\n'
                            'Por favor, tomar as providências cabíveis.',
                          );
                          final uri = Uri.parse(
                              'mailto:?subject=$subject&body=$body');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.chat, color: Colors.white),
                        label: const Text('WhatsApp',
                            style: TextStyle(color: Colors.white)),
                        onPressed: () async {
                          final uri = Uri.parse(
                              'https://wa.me/?text=$mensagemWhatsApp');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _linhaResultado(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ============= HISTÓRICO =============

  Future<Uint8List> _gerarPdfBytes(List<VehicleLog> logs) async {
    final pdf = pw.Document();

    final titulo = isAdm ? 'Histórico - Auditoria' : 'Meu Histórico';
    final agora = DateTime.now();
    final dataHoraFormatada =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text('SGV - Polícia Civil de Pernambuco',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
          ),
          pw.Header(
            level: 1,
            child: pw.Text(titulo,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Paragraph(
            text: 'Gerado em: $dataHoraFormatada | Usuário: $nome',
          ),
          if (isAdm) pw.Paragraph(text: 'Exibindo histórico completo de todos os usuários.'),
          pw.Paragraph(text: 'Total de registros: ${logs.length}'),
          pw.Divider(),
          pw.SizedBox(height: 10),
          ...logs.map((log) {
            final dataHora =
                '${log.timestamp.day.toString().padLeft(2, '0')}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.year} '
                '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}';
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(log.actionType,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 13)),
                      pw.Text(dataHora,
                          style: pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Divider(),
                  pw.Text('Agente: ${log.agentName}',
                      style: const pw.TextStyle(fontSize: 11)),
                  if (log.placa.isNotEmpty)
                    pw.Text('Placa: ${log.placa} | Modelo: ${log.modelo}',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700)),
                  if (log.quilometragem != null)
                    pw.Text('KM: ${log.quilometragem}',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text('Observações: ${log.observations}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            );
          }),
        ],
      ),
    );

    return await pdf.save();
  }

  void _downloadPdfWeb(Uint8List bytes, String fileName) {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _mostrarAlertaPesquisaNecessaria(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Pesquisa Necessária'),
          ],
        ),
        content: const Text(
          'Por favor, realize a pesquisa do histórico desejado antes de exportar ou enviar.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<VehicleLog> _obterLogsFiltrados(LogProvider logProvider, DateTime? dataInicio, DateTime? dataFim) {
    var logs = isAdm
        ? logProvider.logs.toList()
        : logProvider.logs
            .where((l) => l.agentName.toLowerCase() == nome.toLowerCase())
            .toList();

    if (dataInicio != null) {
      logs = logs.where((l) {
        return l.timestamp.isAfter(dataInicio.subtract(const Duration(days: 1)));
      }).toList();
    }
    if (dataFim != null) {
      logs = logs.where((l) {
        return l.timestamp.isBefore(dataFim.add(const Duration(days: 1)));
      }).toList();
    }

    return logs;
  }

  void _showHistoryScreen(BuildContext context) {
    DateTime? dataInicio;
    DateTime? dataFim;
    bool _pesquisaRealizada = false;

    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.carregarMovimentacoes(agente: isAdm ? null : nome);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.history,
                  color: isAdm
                      ? const Color(0xFF0F172A)
                      : Colors.blue.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAdm ? 'Histórico - Auditoria' : 'Meu Histórico',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 500,
            child: Column(
              children: [
                if (_pesquisaRealizada)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.filter_alt, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Pesquisa ativa – os dados exibidos podem ser exportados.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(dataInicio == null
                              ? 'Data Início'
                              : '${dataInicio!.day}/${dataInicio!.month}/${dataInicio!.year}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dataInicio ?? DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setStateModal(() {
                                dataInicio = picked;
                                _pesquisaRealizada = true;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(dataFim == null
                              ? 'Data Fim'
                              : '${dataFim!.day}/${dataFim!.month}/${dataFim!.year}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dataFim ?? DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setStateModal(() {
                                dataFim = picked;
                                _pesquisaRealizada = true;
                              });
                            }
                          },
                        ),
                      ),
                      if (dataInicio != null || dataFim != null)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          tooltip: 'Limpar Filtros',
                          onPressed: () => setStateModal(() {
                            dataInicio = null;
                            dataFim = null;
                            _pesquisaRealizada = false;
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Consumer<LogProvider>(
                    builder: (context, logProvider, child) {
                      if (logProvider.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final logsFiltrados =
                          _obterLogsFiltrados(logProvider, dataInicio, dataFim);

                      if (logsFiltrados.isEmpty) {
                        return const Center(
                          child: Text(
                            'Nenhum registro encontrado para o período/usuário.',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: logsFiltrados.length,
                        itemBuilder: (context, index) {
                          final log = logsFiltrados[index];
                          final corAcao = log.actionType.contains('Saída')
                              ? Colors.blue.shade800
                              : (log.actionType.contains('Devolução') ||
                                      log.actionType.contains('Entrada'))
                                  ? Colors.green.shade800
                                  : const Color(0xFF1E3A8A);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(log.actionType,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: corAcao)),
                                      Text(
                                        '${log.timestamp.day.toString().padLeft(2, '0')}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.year} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Text('Agente: ${log.agentName}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  if (log.placa.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                        'Placa: ${log.placa} | Modelo: ${log.modelo}',
                                        style: const TextStyle(
                                            fontSize: 13, color: Colors.grey)),
                                  ],
                                  if (log.quilometragem != null) ...[
                                    const SizedBox(height: 2),
                                    Text('KM: ${log.quilometragem}',
                                        style: const TextStyle(
                                            fontSize: 13, color: Colors.grey)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                      'Detalhes / Observações: ${log.observations}'),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Salvar em PDF',
                  style: TextStyle(fontSize: 12)),
              onPressed: () async {
                if (!_pesquisaRealizada) {
                  _mostrarAlertaPesquisaNecessaria(context);
                  return;
                }

                final provider =
                    Provider.of<LogProvider>(context, listen: false);
                final logsParaPdf =
                    _obterLogsFiltrados(provider, dataInicio, dataFim);

                if (logsParaPdf.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Não há registros para exportar.'),
                          backgroundColor: Colors.orange),
                    );
                  }
                  return;
                }

                try {
                  final pdfBytes = await _gerarPdfBytes(logsParaPdf);
                  final agora = DateTime.now();
                  final fileName = 'historico_sgv_${agora.millisecondsSinceEpoch}.pdf';
                  if (context.mounted) {
                    _downloadPdfWeb(pdfBytes, fileName);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('PDF salvo com sucesso! (${logsParaPdf.length} registros)'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao gerar o PDF: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Enviar WhatsApp',
                  style: TextStyle(fontSize: 12)),
              onPressed: () async {
                if (!_pesquisaRealizada) {
                  _mostrarAlertaPesquisaNecessaria(context);
                  return;
                }

                final provider =
                    Provider.of<LogProvider>(context, listen: false);
                final logsParaPdf =
                    _obterLogsFiltrados(provider, dataInicio, dataFim);

                if (logsParaPdf.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Não há registros para exportar.'),
                          backgroundColor: Colors.orange),
                    );
                  }
                  return;
                }

                try {
                  final pdfBytes = await _gerarPdfBytes(logsParaPdf);
                  final agora = DateTime.now();
                  final fileName = 'historico_sgv_${agora.millisecondsSinceEpoch}.pdf';

                  if (context.mounted) {
                    _downloadPdfWeb(pdfBytes, fileName);
                    try {
                      await Share.shareXFiles(
                        [XFile.fromData(pdfBytes, name: fileName, mimeType: 'application/pdf')],
                        subject: isAdm ? 'Histórico - Auditoria' : 'Meu Histórico',
                        text: 'Segue o relatório de histórico - SGV PCPE',
                      );
                    } catch (_) {}
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao compartilhar o PDF: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Exibe os resultados da busca de infrações por placa
  void _mostrarResultadosBuscaInfracao(BuildContext context, String placa, List<dynamic> resultados) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.search, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Infrações — Placa: $placa'),
          ],
        ),
        content: SizedBox(
          width: 550,
          height: 400,
          child: resultados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma infração encontrada\npara a placa $placa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: resultados.length,
                  itemBuilder: (context, index) {
                    final inf = resultados[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.gavel, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Auto: ${inf['numero_auto'] ?? 'N/A'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _linhaResultado('Placa', inf['placa_viatura'] ?? ''),
                            _linhaResultado('Local', inf['local'] ?? 'Não informado'),
                            _linhaResultado('Data/Hora',
                                _formatarDataNotificacao(inf['data_hora'] ?? inf['criado_em'])),
                            if ((inf['motorista_identificado'] ?? '').toString().isNotEmpty)
                              _linhaResultado('Motorista', inf['motorista_identificado']),
                            _linhaResultado('Agente Resp.', inf['agente_responsavel'] ?? ''),
                            if (inf['modelo'] != null)
                              _linhaResultado('Viatura', '${inf['modelo']}${inf['cor'] != null ? ' (${inf['cor']})' : ''}'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  // ============= PAINEL DE MANUTENÇÃO =============
  void _abrirPainelManutencao(BuildContext context) {
    String? _placaSelecionada;
    List<dynamic> _manutencoesViatura = [];
    bool _carregando = false;
    String? _modeloViatura;
    int? _kmInicial;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.build, color: Colors.red),
              SizedBox(width: 8),
              Text('Painel de Manutenção'),
            ],
          ),
          content: SizedBox(
            width: 700,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seletor de viatura
                const Text('Selecione a viatura:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                FutureBuilder<List<String>>(
                  future: _fetchPlacasDisponiveis(),
                  builder: (context, snapshot) {
                    final placas = snapshot.data ?? [];
                    return DropdownButtonFormField<String>(
                      value: _placaSelecionada,
                      decoration: const InputDecoration(
                        labelText: 'Placa da Viatura',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.directions_car),
                      ),
                      hint: const Text('Escolha uma placa...'),
                      isExpanded: true,
                      items: placas.map((p) {
                        return DropdownMenuItem(value: p, child: Text(p));
                      }).toList(),
                      onChanged: snapshot.connectionState == ConnectionState.waiting
                          ? null
                          : (v) async {
                              _placaSelecionada = v;
                              _manutencoesViatura = [];
                              _modeloViatura = null;
                              _kmInicial = null;
                              if (v == null || v.isEmpty) {
                                setDialogState(() {});
                                return;
                              }
                              setDialogState(() => _carregando = true);
                              try {
                                final veiculo = await ApiService.buscarVeiculoPorPlaca(v);
                                _modeloViatura = veiculo['modelo'] ?? '';
                                _kmInicial = veiculo['quilometragem_inicial'];
                                final raw = await ApiService.verificarAlertasManutencao(v);
                                // Remove duplicatas por nome do componente (mantém o primeiro)
                                final seen = <String>{};
                                _manutencoesViatura = raw.where((item) {
                                  final comp = (item['componente'] ?? '').toString();
                                  if (seen.contains(comp)) return false;
                                  seen.add(comp);
                                  return true;
                                }).toList();
                              } catch (_) {
                                _manutencoesViatura = [];
                              }
                              _carregando = false;
                              setDialogState(() {});
                            },
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Conteúdo: lista de manutenções ou estado vazio
                Expanded(
                  child: _placaSelecionada == null || _placaSelecionada!.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('Selecione uma viatura acima\npara visualizar suas manutenções.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : _carregando
                          ? const Center(child: CircularProgressIndicator())
                          : _manutencoesViatura.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.green, size: 64),
                                      const SizedBox(height: 16),
                                      Text(
                                        _placaSelecionada != null
                                            ? 'Viatura $_placaSelecionada sem manutenções pendentes!'
                                            : 'Nenhuma manutenção pendente!',
                                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Esta viatura está com a manutenção em dia.',
                                        style: TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView(
                                  children: [
                                    // Cabeçalho da viatura
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.red.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$_placaSelecionada${_modeloViatura != null && _modeloViatura!.isNotEmpty ? ' — $_modeloViatura' : ''}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                          ),
                                          if (_kmInicial != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text('KM Inicial: $_kmInicial',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Colors.black87)),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const Text('Itens pendentes:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    // Lista de itens
                                    ..._manutencoesViatura.map((item) {
                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.warning,
                                                  color: Colors.orange, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['componente'] ?? '',
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Limite: ${item['km_limite'] ?? '?'} km | Atual: ${item['km_atual'] ?? '?'} km',
                                                      style: const TextStyle(
                                                          fontSize: 12, color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isAdm)
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green.shade700,
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 12, vertical: 8),
                                                  ),
                                                  icon: const Icon(Icons.check,
                                                      color: Colors.white, size: 16),
                                                  label: const Text('Baixa',
                                                      style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12)),
                                                  onPressed: () async {
                                                    final confirmar =
                                                        await showDialog<bool>(
                                                      context: context,
                                                      builder: (_) => AlertDialog(
                                                        title:
                                                            const Text('Confirmar Baixa'),
                                                        content: Text(
                                                            'Deseja dar baixa em "${item['componente']}" da viatura $_placaSelecionada?'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(_, false),
                                                            child: const Text('Cancelar'),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () =>
                                                                Navigator.pop(_, true),
                                                            child: const Text('Confirmar'),
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (confirmar == true) {
                                                      await ApiService.baixarManutencao(
                                                        placa: _placaSelecionada!,
                                                        componente: item['componente'],
                                                        baixadoPor: nome,
                                                      );
                                                      // Recarrega a lista
                                                      _manutencoesViatura =
                                                          await ApiService
                                                              .verificarAlertasManutencao(
                                                                  _placaSelecionada!);
                                                      setDialogState(() {});
                                                      ScaffoldMessenger.of(context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Baixa realizada: ${item['componente']}'),
                                                          backgroundColor: Colors.green,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    // Botão Baixar Todas (apenas ADM)
                                    if (isAdm && _manutencoesViatura.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green.shade800,
                                          ),
                                          icon: const Icon(Icons.done_all,
                                              color: Colors.white, size: 18),
                                          label: const Text('Baixar Todas',
                                              style: TextStyle(
                                                  color: Colors.white, fontSize: 12)),
                                          onPressed: () async {
                                            final confirmar = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title:
                                                    const Text('Confirmar Baixa Total'),
                                                content: Text(
                                                    'Deseja dar baixa em TODAS as manutenções pendentes da viatura $_placaSelecionada?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(_, false),
                                                    child: const Text('Cancelar'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(_, true),
                                                    child: const Text('Confirmar'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirmar == true) {
                                              await ApiService.baixarManutencao(
                                                placa: _placaSelecionada!,
                                                baixarTodas: true,
                                                baixadoPor: nome,
                                              );
                                              _manutencoesViatura = await ApiService
                                                  .verificarAlertasManutencao(
                                                      _placaSelecionada!);
                                              setDialogState(() {});
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Todas as manutenções da $_placaSelecionada foram baixadas!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  // ============= MODAL DE REGISTRO DE ABASTECIMENTO =============
  void _abrirModalAbastecimento(BuildContext context) {
    final _placaController = TextEditingController();
    final _litrosController = TextEditingController();
    final _valorController = TextEditingController();
    final _postoController = TextEditingController();
    final _kmController = TextEditingController();
    String _tipoCombustivel = 'Gasolina Comum';
    bool _salvando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_gas_station, color: Colors.orange),
              SizedBox(width: 8),
              Text('Registro de Abastecimento'),
            ],
          ),
          content: Form(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlacaAutocomplete(
                    controller: _placaController,
                    onPlacaSelecionada: (_) {},
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _kmController,
                    decoration: const InputDecoration(
                        labelText: 'KM Atual',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _litrosController,
                          decoration: const InputDecoration(
                              labelText: 'Litros',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _valorController,
                          decoration: const InputDecoration(
                              labelText: 'Valor Total (R\$)',
                              border: OutlineInputBorder()),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _tipoCombustivel,
                    decoration: const InputDecoration(
                        labelText: 'Combustível',
                        border: OutlineInputBorder()),
                    items: [
                      'Gasolina Comum',
                      'Gasolina Aditivada',
                      'Etanol',
                      'Diesel S10',
                      'Diesel Comum'
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) =>
                        setDialogState(() => _tipoCombustivel = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _postoController,
                    decoration: const InputDecoration(
                        labelText: 'Posto', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(_salvando ? 'Salvando...' : 'Registrar',
                  style: const TextStyle(color: Colors.white)),
              onPressed: _salvando
                  ? null
                  : () async {
                      if (_placaController.text.isEmpty ||
                          _kmController.text.isEmpty ||
                          _litrosController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Preencha todos os campos obrigatórios'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => _salvando = true);

                      Provider.of<LogProvider>(context, listen: false).addLog(
                        agentName: nome,
                        actionType: 'Abastecimento',
                        observations:
                            '⛽ Abastecimento: ${_litrosController.text}L de $_tipoCombustivel'
                            ' no posto ${_postoController.text.isNotEmpty ? _postoController.text : "Não informado"}'
                            '${_valorController.text.isNotEmpty ? ' - Valor: R\$ ${_valorController.text}' : ''}',
                        placa: _placaController.text.toUpperCase(),
                        modelo: '',
                        quilometragem:
                            int.tryParse(_kmController.text.replaceAll(RegExp(r'[^0-9]'), '')),
                      );

                      try {
                        final response = await ApiService.registrarMovimentacao({
                          'agente_nome': nome,
                          'tipo_movimento': 'Abastecimento',
                          'placa':
                              _placaController.text.toUpperCase().trim(),
                          'quilometragem':
                              _kmController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                          'observacoes':
                              'Abastecimento: ${_litrosController.text}L de $_tipoCombustivel'
                                  ' - Posto: ${_postoController.text.isNotEmpty ? _postoController.text : "Não informado"}'
                                  '${_valorController.text.isNotEmpty ? " - Valor: R\$ ${_valorController.text}" : ""}',
                        });
                        setDialogState(() => _salvando = false);

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(response
                                ? 'Abastecimento registrado com sucesso!'
                                : 'Erro ao registrar abastecimento no servidor.'),
                            backgroundColor: response ? Colors.green : Colors.red,
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => _salvando = false);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Erro de conexão: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ============= MODAL DE GESTÃO DE ADMINISTRADORES =============
  void _abrirModalGestaoAdmins(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    final _cpfController = TextEditingController();
    final _nomeController = TextEditingController();
    final _emailController = TextEditingController();
    String _cargoSelecionado = 'Agente';
    final _senhaController = TextEditingController();
    final _buscaController = TextEditingController();
    String _perfilSelecionado = 'Administrador'; // 'Administrador' ou 'Master'
    bool _salvandoAdm = false;
    String _termoBusca = '';
    int _reloadCounter = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('Cadastro de Administradores'),
            ],
          ),
          content: SizedBox(
            width: 700,
            height: 550,
            child: Column(
              children: [
                ExpansionTile(
                  initiallyExpanded: true,
                  title: const Text('Cadastrar Novo Usuário',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _cpfController,
                              decoration: const InputDecoration(
                                  labelText: 'CPF (apenas números)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge)),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe o CPF';
                                }
                                final cpfLimpo = v.replaceAll(RegExp(r'[^0-9]'), '');
                                if (cpfLimpo.length != 11) {
                                  return 'CPF deve ter 11 dígitos';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nomeController,
                              decoration: const InputDecoration(
                                  labelText: 'Nome Completo',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person)),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Informe o nome' : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                  labelText: 'E-mail',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email)),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: _cargoSelecionado,
                              decoration: const InputDecoration(
                                  labelText: 'Cargo',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.work)),
                              items: const [
                                DropdownMenuItem(value: 'Agente', child: Text('Agente')),
                                DropdownMenuItem(value: 'Delegado', child: Text('Delegado')),
                                DropdownMenuItem(value: 'Escrivão', child: Text('Escrivão')),
                              ],
                              onChanged: (v) =>
                                  setDialogState(() => _cargoSelecionado = v!),
                            ),
                            const SizedBox(height: 10),
                            // Dropdown de Perfil (hierarquia)
                            if (isMaster)
                              DropdownButtonFormField<String>(
                                value: _perfilSelecionado,
                                decoration: const InputDecoration(
                                    labelText: 'Perfil de Acesso',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.security)),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Administrador',
                                      child: Text('Administrador')),
                                  DropdownMenuItem(
                                      value: 'Master',
                                      child: Row(
                                        children: [
                                          Text('Master'),
                                          SizedBox(width: 6),
                                          Icon(Icons.star, color: Colors.amber, size: 14),
                                        ],
                                      )),
                                ],
                                onChanged: (v) =>
                                    setDialogState(() => _perfilSelecionado = v!),
                              ),
                            if (isMaster) const SizedBox(height: 10),
                            TextFormField(
                              controller: _senhaController,
                              decoration: const InputDecoration(
                                  labelText: 'Senha (padrão: 123456)',
                                  hintText: 'Deixe em branco para usar a senha padrão',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock)),
                              obscureText: true,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: _salvandoAdm
                                    ? const SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.person_add, color: Colors.white),
                                label: Text(
                                  _salvandoAdm ? 'Cadastrando...' : 'Cadastrar Usuário',
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                                onPressed: _salvandoAdm
                                    ? null
                                    : () async {
                                        if (_formKey.currentState!.validate()) {
                                          setDialogState(() => _salvandoAdm = true);

                                          final resultado = await ApiService.cadastrarAdmin(
                                            cpf: _cpfController.text.trim(),
                                            nome: _nomeController.text.trim(),
                                            email: _emailController.text.trim(),
                                            cargo: _cargoSelecionado,
                                            senha: _senhaController.text.trim().isNotEmpty
                                                ? _senhaController.text.trim()
                                                : '123456',
                                            adminSolicitanteCpf: cpf,
                                            isMaster: _perfilSelecionado == 'Master',
                                          );

                                          setDialogState(() => _salvandoAdm = false);

                                          if (!ctx.mounted) return;

                                          if (resultado['sucesso'] == true) {
                                            _cpfController.clear();
                                            _nomeController.clear();
                                            _emailController.clear();
                                            _cargoSelecionado = 'Agente';
                                            _senhaController.clear();
                                            _perfilSelecionado = 'Administrador';
                                            _reloadCounter++;
                                            setDialogState(() {});
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(resultado['mensagem'] ??
                                                    'Usuário cadastrado com sucesso!'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(resultado['mensagem'] ??
                                                    'Erro ao cadastrar usuário.'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                // Campo de Busca Dinâmica
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: TextField(
                    controller: _buscaController,
                    decoration: InputDecoration(
                      labelText: '🔍 Buscar por Nome, CPF ou E-mail',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _termoBusca.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _buscaController.clear();
                                setDialogState(() => _termoBusca = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) {
                      setDialogState(() => _termoBusca = v.toLowerCase().trim());
                    },
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Usuários Cadastrados',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 4),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    key: ValueKey<int>(_reloadCounter),
                    future: ApiService.listarUsuarios(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Carregando usuários...',
                                  style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                              const SizedBox(height: 12),
                              const Text('Erro ao carregar usuários.',
                                  style: TextStyle(fontSize: 14, color: Colors.red)),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Tentar novamente'),
                                onPressed: () {
                                  _reloadCounter++;
                                  setDialogState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('Nenhum usuário cadastrado.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text('Cadastre o primeiro usuário acima.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ],
                          ),
                        );
                      }

                      final todosUsuarios = snapshot.data!;

                      // Filtro de busca case-insensitive
                      final usuarios = _termoBusca.isEmpty
                          ? todosUsuarios
                          : todosUsuarios.where((u) {
                              final nome = (u['nome'] ?? '').toString().toLowerCase();
                              final cpf = (u['cpf'] ?? '').toString().toLowerCase();
                              final email = (u['email'] ?? '').toString().toLowerCase();
                              return nome.contains(_termoBusca) ||
                                  cpf.contains(_termoBusca) ||
                                  email.contains(_termoBusca);
                            }).toList();

                      if (usuarios.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum usuário corresponde à busca "${_buscaController.text}".',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        itemCount: usuarios.length,
                        itemBuilder: (context, index) {
                          final u = usuarios[index];
                          final userIsMaster = u['is_master'] == true;
                          final userIsAdmin = u['is_adm'] == true;
                          final cargo = (u['cargo'] ?? 'Agente').toString();
                          final emailUser = (u['email'] ?? '').toString();
                          final cpfUser = (u['cpf'] ?? '').toString();
                          final nomeUser = (u['nome'] ?? 'Sem nome').toString();

                          // Define cor e ícone conforme perfil
                          final Color perfilCor;
                          final IconData perfilIcon;
                          final String perfilLabel;
                          if (userIsMaster) {
                            perfilCor = Colors.amber.shade700;
                            perfilIcon = Icons.shield;
                            perfilLabel = 'Master';
                          } else if (userIsAdmin) {
                            perfilCor = Colors.deepPurple;
                            perfilIcon = Icons.admin_panel_settings;
                            perfilLabel = 'Administrador';
                          } else {
                            perfilCor = Colors.blueGrey;
                            perfilIcon = Icons.person;
                            perfilLabel = 'Usuário';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Linha 1: Avatar + Nome + Badge de perfil
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: perfilCor.withOpacity(0.12),
                                        child: Icon(perfilIcon,
                                            color: perfilCor, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nomeUser,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  color: Color(0xFF1E293B)),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              cargo,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: perfilCor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: perfilCor.withOpacity(0.3),
                                              width: 1),
                                        ),
                                        child: Text(
                                          perfilLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: perfilCor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Linha 2: Divisor
                                  Container(
                                    height: 1,
                                    color: Colors.grey.shade200,
                                  ),
                                  const SizedBox(height: 10),
                                  // Linha 3: CPF e E-mail lado a lado
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoChip(
                                          Icons.badge_outlined,
                                          'CPF',
                                          _formatarCpf(cpfUser),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (emailUser.isNotEmpty)
                                        Expanded(
                                          flex: 2,
                                          child: _buildInfoChip(
                                            Icons.email_outlined,
                                            'E-mail',
                                            emailUser,
                                          ),
                                        ),
                                    ],
                                  ),
                                  // Botão excluir para Master
                                  if (isMaster && !userIsMaster) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red.shade600,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                        ),
                                        icon: const Icon(Icons.delete_outline,
                                            size: 16),
                                        label: const Text('Excluir',
                                            style: TextStyle(fontSize: 12)),
                                        onPressed: () async {
                                          final confirmar =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: const Text(
                                                  'Confirmar Exclusão'),
                                              content: Text(
                                                  'Deseja realmente excluir o usuário "$nomeUser"?\n\nEsta ação não pode ser desfeita.'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(_, false),
                                                  child: const Text('Cancelar'),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.red),
                                                  onPressed: () =>
                                                      Navigator.pop(_, true),
                                                  child: const Text('Excluir',
                                                      style: TextStyle(
                                                          color: Colors.white)),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirmar == true) {
                                            final resultado =
                                                await ApiService.excluirUsuario(
                                              usuarioId: u['id'],
                                              adminSolicitanteCpf: cpf,
                                            );

                                            if (!ctx.mounted) return;

                                            if (resultado['sucesso'] == true) {
                                              _reloadCounter++;
                                              setDialogState(() {});
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      resultado['mensagem'] ??
                                                          'Usuário excluído com sucesso.'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      resultado['mensagem'] ??
                                                          'Erro ao excluir usuário.'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                _buscaController.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  // ============= MÉTODO AUXILIAR: INFO CHIP (CARDS DE USUÁRIOS) =============
  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============= MÉTODO AUXILIAR: LISTA DE PLACAS =============
  List<dynamic>? _cachedViaturas;

  Future<List<dynamic>> _fetchViaturas() async {
    if (_cachedViaturas != null) return _cachedViaturas!;
    _cachedViaturas = await ApiService.listarTodasViaturas();
    return _cachedViaturas ?? [];
  }

  Future<List<String>> _fetchPlacasDisponiveis() async {
    final viaturas = await _fetchViaturas();
    return viaturas
        .map<String>((v) => (v['placa'] ?? '').toString().toUpperCase())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  /// Widget reutilizável: Autocomplete de Placa com busca no backend
  Widget _buildPlacaAutocomplete({
    required TextEditingController controller,
    required ValueChanged<String> onPlacaSelecionada,
    String? initialValue,
  }) {
    if (initialValue != null && initialValue.isNotEmpty && controller.text.isEmpty) {
      controller.text = initialValue;
    }
    return FutureBuilder<List<String>>(
      future: _fetchPlacasDisponiveis(),
      builder: (context, snapshot) {
        final placas = snapshot.data ?? [];
        return Autocomplete<String>(
          initialValue: controller.text.isNotEmpty
              ? TextEditingValue(text: controller.text)
              : null,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return placas;
            }
            final filtro = textEditingValue.text.toUpperCase();
            return placas.where((p) => p.contains(filtro));
          },
          onSelected: (String selection) {
            controller.text = selection;
            onPlacaSelecionada(selection);
          },
          fieldViewBuilder: (context, fieldController, focusNode, onEditingComplete) {
            // Sincroniza o controller externo com o interno do Autocomplete
            if (controller.text.isNotEmpty && fieldController.text.isEmpty) {
              fieldController.text = controller.text;
            }
            return TextField(
              controller: fieldController,
              focusNode: focusNode,
              onEditingComplete: onEditingComplete,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Placa da Viatura',
                hintText: 'Digite ou selecione a placa',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.directions_car),
                suffixIcon: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(width: 20, height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ))
                    : (controller.text.isNotEmpty && placas.contains(controller.text.toUpperCase())
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null),
              ),
              onChanged: (value) {
                controller.text = value.toUpperCase();
                final match = placas.where(
                    (p) => p == value.toUpperCase()).toList();
                if (match.isNotEmpty) {
                  onPlacaSelecionada(match.first);
                }
              },
            );
          },
        );
      },
    );
  }

  // ============= BOTTOM NAVIGATION HANDLER =============
  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  // ============= ABA 0: INÍCIO =============
  Widget _buildInicioTab() {
    final List<Widget> modulosPermitidos = [
      _buildModuleCard(
          context,
          'Saída de Viatura',
          Icons.exit_to_app,
          Colors.blue.shade800,
          true,
          () => _showModuleScreen(context, 'Saída de Viatura', true)),
      _buildModuleCard(
          context,
          'Devolução de Viatura',
          Icons.login,
          Colors.green.shade800,
          true,
          () => _showModuleScreen(context, 'Devolução de Viatura', true)),
      _buildModuleCard(
          context,
          'Registro de Abastecimento',
          Icons.local_gas_station,
          Colors.orange.shade800,
          false,
          () => _abrirModalAbastecimento(context)),
      _buildModuleCard(context, 'Meu Histórico', Icons.history,
          Colors.indigo.shade700, false, () => _showHistoryScreen(context)),
      _buildModuleCard(context, 'Manutenção', Icons.build,
          Colors.red.shade800, false, () => _abrirPainelManutencao(context)),
    ];

    if (isAdm) {
      modulosPermitidos.addAll([
        _buildModuleCard(
            context,
            'Cadastro de Viaturas',
            Icons.directions_car,
            Colors.teal.shade800,
            false,
            () => _abrirModalGestaoViaturas(context)),
        _buildModuleCard(
            context,
            'Gestão de Infrações',
            Icons.gavel,
            Colors.orange.shade800,
            false,
            () => _abrirModalInfracoes(context)),
        _buildModuleCard(
            context,
            'Cadastro de Administradores',
            Icons.admin_panel_settings,
            Colors.deepPurple.shade800,
            false,
            () => _abrirModalGestaoAdmins(context)),
      ]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('Bem-vindo, $nome',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (isAdm)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text('ADMIN',
                            style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 9)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${cargo.isNotEmpty ? cargo : 'Usuário'} | CPF: $cpf',
                    style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text('Login: $horaLogin',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('Módulos Operacionais',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 120,
            ),
            itemCount: modulosPermitidos.length,
            itemBuilder: (context, index) => modulosPermitidos[index],
          ),
          const SizedBox(height: 70),
        ],
      ),
    );
  }

  // ============= ABA 1: NOTIFICAÇÕES =============
  /// Força recarregar as notificações ao trocar de aba
  void _recarregarNotificacoes() {
    // Método chamado via setState para forçar rebuild do FutureBuilder
  }

  Widget _buildNotificacoesTab() {
    // Filtros locais (stateful)
    String _filtroTipoSelecionado = '';
    final _filtroNomeController = TextEditingController();
    DateTime? _filtroDataInicio;
    DateTime? _filtroDataFim;
    bool _filtrosVisiveis = false;
    bool _precisaRecarregar = false;

    return StatefulBuilder(
      builder: (context, setDialogState) {
        Future<List<dynamic>> _carregarNotificacoes() async {
          if (isAdm) {
            return await ApiService.buscarTodasNotificacoes(
              tipo: _filtroTipoSelecionado.isNotEmpty ? _filtroTipoSelecionado : null,
              nome: _filtroNomeController.text.trim().isNotEmpty ? _filtroNomeController.text.trim() : null,
              dataInicio: _filtroDataInicio != null
                  ? '${_filtroDataInicio!.year}-${_filtroDataInicio!.month.toString().padLeft(2, '0')}-${_filtroDataInicio!.day.toString().padLeft(2, '0')}'
                  : null,
              dataFim: _filtroDataFim != null
                  ? '${_filtroDataFim!.year}-${_filtroDataFim!.month.toString().padLeft(2, '0')}-${_filtroDataFim!.day.toString().padLeft(2, '0')}'
                  : null,
            );
          } else {
            return await ApiService.buscarNotificacoes(cpf);
          }
        }

        return Column(
          children: [
            // Barra de filtros (apenas visível para ADM)
            if (isAdm) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: InkWell(
                  onTap: () => setDialogState(() => _filtrosVisiveis = !_filtrosVisiveis),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 8),
                        const Text('Filtros de Pesquisa',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        const Spacer(),
                        Icon(_filtrosVisiveis ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
              if (_filtrosVisiveis)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      // Linha 1: Tipo e Nome
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filtroTipoSelecionado.isEmpty ? null : _filtroTipoSelecionado,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                isDense: true,
                              ),
                              hint: const Text('Todos', style: TextStyle(fontSize: 13)),
                              items: ['multa', 'aviso', 'ocorrencia'].map((t) {
                                String label;
                                switch (t) {
                                  case 'multa': label = 'Multa'; break;
                                  case 'aviso': label = 'Manutenção'; break;
                                  case 'ocorrencia': label = 'Ocorrência'; break;
                                  default: label = t;
                                }
                                return DropdownMenuItem(value: t, child: Text(label));
                              }).toList(),
                              onChanged: (v) {
                                _filtroTipoSelecionado = v ?? '';
                                _precisaRecarregar = true;
                                setDialogState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _filtroNomeController,
                              decoration: const InputDecoration(
                                labelText: 'Nome do Usuário',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                isDense: true,
                                prefixIcon: Icon(Icons.person, size: 18),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (_) {
                                _precisaRecarregar = true;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Linha 2: Datas e botões
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 14),
                              label: Text(
                                _filtroDataInicio == null
                                    ? 'Data Início'
                                    : '${_filtroDataInicio!.day.toString().padLeft(2, '0')}/${_filtroDataInicio!.month.toString().padLeft(2, '0')}/${_filtroDataInicio!.year}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _filtroDataInicio ?? DateTime.now(),
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  _filtroDataInicio = picked;
                                  _precisaRecarregar = true;
                                  setDialogState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 14),
                              label: Text(
                                _filtroDataFim == null
                                    ? 'Data Fim'
                                    : '${_filtroDataFim!.day.toString().padLeft(2, '0')}/${_filtroDataFim!.month.toString().padLeft(2, '0')}/${_filtroDataFim!.year}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _filtroDataFim ?? DateTime.now(),
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  _filtroDataFim = picked;
                                  _precisaRecarregar = true;
                                  setDialogState(() {});
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: const Icon(Icons.search, color: Colors.white, size: 16),
                          label: const Text('Aplicar Filtros',
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                          onPressed: () {
                            _precisaRecarregar = true;
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
            ],

            // Lista de notificações
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _carregarNotificacoes(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('Nenhuma notificação no momento.',
                              style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          Text(
                            isAdm
                                ? 'Notificações de todos os usuários aparecerão aqui.\nUse os filtros para refinar a busca.'
                                : 'Os alertas de manutenção, infrações e vistorias\naparecerão aqui automaticamente.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    );
                  }

                  final notificacoes = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async => setDialogState(() {}),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      itemCount: notificacoes.length,
                      itemBuilder: (context, index) {
                        final n = notificacoes[index];
                        final bool lida = n['lida'] == true;
                        final String tipo = n['tipo'] ?? 'info';
                        IconData icone;
                        Color cor;
                        switch (tipo) {
                          case 'aviso':
                            icone = Icons.warning_amber_rounded;
                            cor = Colors.orange;
                            break;
                          case 'multa':
                            icone = Icons.gavel;
                            cor = Colors.red;
                            break;
                          case 'ocorrencia':
                            icone = Icons.report_problem;
                            cor = Colors.deepOrange;
                            break;
                          default:
                            icone = Icons.info_outline;
                            cor = Colors.blue;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: lida ? Colors.white : Colors.blue.shade50,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cor.withOpacity(0.15),
                              child: Icon(icone, color: cor, size: 22),
                            ),
                            title: Text(n['titulo'] ?? '',
                                style: TextStyle(
                                    fontWeight: lida ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 14)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((n['mensagem'] ?? '').toString().isNotEmpty)
                                  Text(n['mensagem'], style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if ((n['placa'] ?? '').toString().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4)),
                                        child: Text('Placa: ${n['placa']}',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                      ),
                                    // Nome do usuário (apenas para ADM)
                                    if (isAdm && (n['nome_usuario'] ?? '').toString().isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.deepPurple.shade50,
                                            borderRadius: BorderRadius.circular(4)),
                                        child: Text(
                                          n['nome_usuario'],
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade700),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(_formatarDataNotificacao(n['data_ocorrencia'] ?? n['criado_em']),
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ],
                            ),
                            trailing: lida
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                    tooltip: 'Marcar como lida',
                                    onPressed: () async {
                                      final sucesso = await ApiService.marcarNotificacaoLida(n['id']);
                                      if (sucesso && context.mounted) {
                                        setDialogState(() {});
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Notificação marcada como lida.'),
                                              backgroundColor: Colors.green),
                                        );
                                      }
                                    },
                                  ),
                            onTap: lida
                                ? null
                                : () async {
                                    await ApiService.marcarNotificacaoLida(n['id']);
                                    setDialogState(() {});
                                  },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatarDataNotificacao(dynamic data) {
    if (data == null) return '';
    try {
      final dt = DateTime.parse(data.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return data.toString();
    }
  }

  // ============= ABA 2: SERVIÇOS =============
  int _servicosSubTabIndex = 0;

  Widget _buildServicosTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _servicosSubTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _servicosSubTabIndex == 0 ? const Color(0xFF0F172A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Manutenção / Avaria',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _servicosSubTabIndex == 0 ? Colors.amberAccent : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _servicosSubTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _servicosSubTabIndex == 1 ? const Color(0xFF0F172A) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Checklist Diário',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _servicosSubTabIndex == 1 ? Colors.amberAccent : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _servicosSubTabIndex == 0
              ? _buildSolicitacoesManutencaoTab()
              : _buildChecklistTab(),
        ),
      ],
    );
  }

  // --- Sub-aba: Solicitações de Manutenção ---
  Widget _buildSolicitacoesManutencaoTab() {
    final _placaController = TextEditingController();
    final _descricaoController = TextEditingController();
    String _tipoProblemaSelecionado = 'Problema Mecânico';
    bool _enviandoSolicitacao = false;

    final List<String> _tiposProblema = [
      'Problema Mecânico',
      'Problema Elétrico',
      'Suspensão / Direção',
      'Freios',
      'Pneus',
      'Lataria / Pintura',
      'Ar-condicionado',
      'Vidros / Retrovisores',
      'Sistema de Iluminação',
      'Outro',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          // --- Formulário de nova solicitação ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text('Nova Solicitação',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                TextField(
                  controller: _placaController,
                  decoration: const InputDecoration(
                      labelText: 'Placa da Viatura',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car)),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _tipoProblemaSelecionado,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de Problema',
                      border: OutlineInputBorder()),
                  items: _tiposProblema
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipoProblemaSelecionado = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descricaoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Descrição detalhada',
                      hintText: 'Descreva o problema observado...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _enviandoSolicitacao
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(
                        _enviandoSolicitacao ? 'Enviando...' : 'Enviar Solicitação',
                        style: const TextStyle(color: Colors.white)),
                    onPressed: _enviandoSolicitacao
                        ? null
                        : () async {
                            if (_placaController.text.trim().isEmpty ||
                                _descricaoController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Preencha placa e descrição.'),
                                    backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setState(() => _enviandoSolicitacao = true);

                            final resultado = await ApiService.criarSolicitacaoManutencao(
                              placa: _placaController.text.trim().toUpperCase(),
                              agenteNome: nome,
                              cpfAgente: cpf,
                              tipoProblema: _tipoProblemaSelecionado,
                              descricao: _descricaoController.text.trim(),
                            );

                            setState(() => _enviandoSolicitacao = false);

                            if (resultado != null) {
                              _placaController.clear();
                              _descricaoController.clear();
                              setState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Solicitação enviada com sucesso!'),
                                      backgroundColor: Colors.green),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Erro ao enviar solicitação.'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // --- Histórico de solicitações ---
          const Text('Minhas Solicitações',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: ApiService.buscarSolicitacoesManutencao(cpf),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text('Nenhuma solicitação registrada.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                );
              }
              final solicitacoes = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: solicitacoes.length,
                itemBuilder: (context, index) {
                  final s = solicitacoes[index];
                  final status = s['status'] ?? 'pendente';
                  Color statusColor;
                  IconData statusIcon;
                  switch (status) {
                    case 'concluido':
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                      break;
                    case 'em_andamento':
                      statusColor = Colors.blue;
                      statusIcon = Icons.autorenew;
                      break;
                    default:
                      statusColor = Colors.orange;
                      statusIcon = Icons.hourglass_empty;
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(statusIcon, color: statusColor),
                      title: Text('${s['placa']} — ${s['tipo_problema']}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((s['descricao'] ?? '').toString().isNotEmpty)
                            Text(s['descricao'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11)),
                          Text('Status: $status | ${_formatarDataNotificacao(s['criado_em'])}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Sub-aba: Checklist Diário ---
  Widget _buildChecklistTab() {
    final _placaController = TextEditingController();
    final _kmController = TextEditingController();
    final _obsController = TextEditingController();
    bool _enviandoChecklist = false;

    final Map<String, bool> _itensChecklist = {
      'Pneus em bom estado': false,
      'Luzes / Faróis': false,
      'Freios': false,
      'Óleo do motor': false,
      'Água do radiador': false,
      'Cintos de segurança': false,
      'Extintor de incêndio': false,
      'Retrovisores': false,
      'Documentos do veículo': false,
      'Limpeza geral': false,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text('Novo Checklist Diário',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                TextField(
                  controller: _placaController,
                  decoration: const InputDecoration(
                      labelText: 'Placa da Viatura',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car)),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _kmController,
                  decoration: const InputDecoration(
                      labelText: 'KM Atual',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.speed)),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                const Text('Itens de Inspeção:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                ..._itensChecklist.keys.map((item) {
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item, style: const TextStyle(fontSize: 13)),
                    value: _itensChecklist[item],
                    onChanged: (v) => setState(() => _itensChecklist[item] = v ?? false),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: _obsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _enviandoChecklist
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.checklist, color: Colors.white),
                    label: Text(
                        _enviandoChecklist ? 'Registrando...' : 'Registrar Checklist',
                        style: const TextStyle(color: Colors.white)),
                    onPressed: _enviandoChecklist
                        ? null
                        : () async {
                            if (_placaController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Informe a placa da viatura.'),
                                    backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setState(() => _enviandoChecklist = true);

                            final resultado = await ApiService.criarChecklist({
                              'placa': _placaController.text.trim().toUpperCase(),
                              'agente_nome': nome,
                              'cpf_agente': cpf,
                              'item_1_pneus': _itensChecklist['Pneus em bom estado'],
                              'item_2_luzes': _itensChecklist['Luzes / Faróis'],
                              'item_3_freios': _itensChecklist['Freios'],
                              'item_4_oleo': _itensChecklist['Óleo do motor'],
                              'item_5_agua': _itensChecklist['Água do radiador'],
                              'item_6_cintos': _itensChecklist['Cintos de segurança'],
                              'item_7_extintor': _itensChecklist['Extintor de incêndio'],
                              'item_8_retrovisores': _itensChecklist['Retrovisores'],
                              'item_9_documentos': _itensChecklist['Documentos do veículo'],
                              'item_10_limpeza': _itensChecklist['Limpeza geral'],
                              'observacoes': _obsController.text.trim(),
                              'km_atual': int.tryParse(
                                  _kmController.text.replaceAll(RegExp(r'[^0-9]'), '')),
                            });

                            setState(() => _enviandoChecklist = false);

                            if (resultado != null) {
                              _placaController.clear();
                              _kmController.clear();
                              _obsController.clear();
                              for (final k in _itensChecklist.keys.toList()) {
                                _itensChecklist[k] = false;
                              }
                              setState(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Checklist registrado com sucesso!'),
                                      backgroundColor: Colors.green),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Erro ao registrar checklist.'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Checklists Anteriores',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: ApiService.buscarChecklists(cpf),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text('Nenhum checklist registrado.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                );
              }
              final checklists = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: checklists.length,
                itemBuilder: (context, index) {
                  final c = checklists[index];
                  final itensOk = [
                    c['item_1_pneus'], c['item_2_luzes'], c['item_3_freios'],
                    c['item_4_oleo'], c['item_5_agua'], c['item_6_cintos'],
                    c['item_7_extintor'], c['item_8_retrovisores'],
                    c['item_9_documentos'], c['item_10_limpeza'],
                  ].where((i) => i == true).length;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: itensOk == 10 ? Colors.green.shade100 : Colors.orange.shade100,
                        child: Text('$itensOk/10',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: itensOk == 10 ? Colors.green : Colors.orange)),
                      ),
                      title: Text('${c['placa']}${c['km_atual'] != null ? ' — KM: ${c['km_atual']}' : ''}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_formatarDataNotificacao(c['criado_em']),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ============= ABA 3: MEUS DADOS =============
  Widget _buildMeusDadosTab() {
    // Garante que o CPF seja enviado limpo (apenas números)
    final cpfLimpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');

    return FutureBuilder<Map<String, dynamic>?>(
      future: cpfLimpo.isNotEmpty
          ? ApiService.buscarDetalhesUsuario(cpfLimpo)
          : Future.value(null),
      builder: (context, snapshot) {
        final bool carregouApi =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data != null;

        // Dados da API como enriquecimento (apenas contadores)
        final totalMov = carregouApi
            ? (snapshot.data!['total_movimentacoes'] ?? 0)
            : 0;
        final totalAbast = carregouApi
            ? (snapshot.data!['total_abastecimentos'] ?? 0)
            : 0;
        final criadoEm = carregouApi
            ? (snapshot.data!['criado_em'] ?? '')
            : '';
        final atualizadoEm = carregouApi
            ? (snapshot.data!['atualizado_em'] ?? '')
            : '';

        // Exibe os dados da sessão como prioridade (sempre disponíveis)
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                      width: 24,
                      height: 2,
                      child: LinearProgressIndicator()),
                ),

              // Avatar + Nome
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF1E3A8A),
                child: Text(
                  nome.isNotEmpty ? nome[0].toUpperCase() : 'U',
                  style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(nome,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(cargo.isNotEmpty ? cargo : 'Agente',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              if (isAdm)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text('Administrador',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.brown)),
                ),
              const SizedBox(height: 24),

              // Cards de estatísticas (apenas se a API retornou)
              Row(
                children: [
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.swap_horiz,
                                color: Color(0xFF1E3A8A), size: 32),
                            const SizedBox(height: 8),
                            Text(
                                carregouApi ? '$totalMov' : '—',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            const Text('Movimentações',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.local_gas_station,
                                color: Colors.orange, size: 32),
                            const SizedBox(height: 8),
                            Text(
                                carregouApi ? '$totalAbast' : '—',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            const Text('Abastecimentos',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Dados detalhados (sessão + o que a API puder enriquecer)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Informações Pessoais',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const Divider(),
                      _linhaDados('CPF', _formatarCpf(cpfLimpo)),
                      const SizedBox(height: 8),
                      _linhaDados(
                          'E-mail',
                          email.isNotEmpty
                              ? email
                              : (carregouApi
                                  ? (snapshot.data!['email'] ?? '')
                                  : '')),
                      const SizedBox(height: 8),
                      _linhaDados('Cargo',
                          cargo.isNotEmpty ? cargo : 'Agente'),
                      const SizedBox(height: 8),
                      _linhaDados(
                          'Tipo de Acesso',
                          isAdm
                              ? 'Administrador'
                              : 'Usuário Padrão'),
                      const SizedBox(height: 8),
                      if (criadoEm.toString().isNotEmpty)
                        _linhaDados('Cadastro em',
                            _formatarDataNotificacao(criadoEm))
                      else
                        _linhaDados('Cadastro em',
                            'Dados do login atual'),
                      if (atualizadoEm.toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _linhaDados('Última atualização',
                            _formatarDataNotificacao(atualizadoEm)),
                      ],
                      if (!carregouApi &&
                          snapshot.connectionState ==
                              ConnectionState.done)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Dados exibidos da sessão atual. Os contadores do servidor '
                                  'não estão disponíveis no momento.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.grey.shade500,
                                      fontStyle:
                                          FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 70),
            ],
          ),
        );
      },
    );
  }

  Widget _linhaDados(String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text('$label:',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Text(valor.isNotEmpty ? valor : '-',
              style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  String _formatarCpf(String cpf) {
    final cpfLimpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpfLimpo.length == 11) {
      return '${cpfLimpo.substring(0, 3)}.${cpfLimpo.substring(3, 6)}.${cpfLimpo.substring(6, 9)}-${cpfLimpo.substring(9)}';
    }
    return cpf;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        toolbarHeight: 48,
        title: Row(
          children: const [
            Icon(Icons.local_police, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Flexible(
              child: Text('SGV - PCPE',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white, size: 20),
              tooltip: 'Sair',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (!context.mounted) return;
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()));
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildInicioTab(),
            _buildNotificacoesTab(),
            _buildServicosTab(),
            _buildMeusDadosTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: const Color(0xFF0F172A),
        selectedItemColor: Colors.amberAccent,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            label: 'Notificações',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.miscellaneous_services_outlined),
            label: 'Serviços',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Meus Dados',
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(BuildContext context, String title, IconData icon,
      Color color, bool isPrimary, VoidCallback onTap) {
    return Card(
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary ? color.withOpacity(0.3) : Colors.grey.shade200,
              width: isPrimary ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  height: 1.2,
                ),
              ),
              if (isPrimary)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Principal',
                      style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}