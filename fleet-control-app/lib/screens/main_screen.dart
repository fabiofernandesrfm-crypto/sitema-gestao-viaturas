import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/log_provider.dart';
import '../services/api_service.dart';
import '../services/ocr_service.dart';
import 'login_screen.dart';

class MainScreen extends StatelessWidget {
  final String nome;
  final String cargo;
  final bool isAdm;
  final String cpf;
  final String email;
  final String horaLogin;

  const MainScreen({
    Key? key,
    required this.nome,
    required this.cargo,
    required this.isAdm,
    required this.cpf,
    required this.email,
    required this.horaLogin,
  }) : super(key: key);

  void _showModuleScreen(BuildContext context, String moduleName, bool hasPhotoFeature) {
    final TextEditingController observationController = TextEditingController();
    final OcrService _ocrService = OcrService();
    
    String placaLida = '';
    String modeloLido = '';
    String corLida = '';
    String kmLido = '';
    bool fotoPlacaTirada = false;
    bool fotoPainelTirada = false;
    bool isLoadingVeiculo = false;

    void atualizarObservacoesAutomaticas(StateSetter setStateModal) {
      List<String> partes = [];
      if (fotoPlacaTirada) {
        partes.add('Placa: $placaLida ($modeloLido - $corLida)');
      }
      if (fotoPainelTirada) {
        partes.add('KM: $kmLido');
      }
      partes.add('Data/Hora: ${DateTime.now().toString().substring(0, 16)}');
      
      observationController.text = partes.join(' | ');
      setStateModal(() {});
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text(moduleName),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Painel de controle para: $moduleName'),
                  const SizedBox(height: 16),
                  if (hasPhotoFeature) ...[
                    const Text(
                      'Captura de Evidências / Fotos:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              setStateModal(() {
                                isLoadingVeiculo = true;
                              });

                              if (moduleName == 'Saída de Viatura') {
                                var usuarioOcupado = await ApiService.verificarUsuarioComSaidaAtiva(nome);
                                
                                if (usuarioOcupado != null) {
                                  setStateModal(() {
                                    isLoadingVeiculo = false;
                                  });
                                  if (!context.mounted) return;
                                  
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Retirada Bloqueada'),
                                      content: const Text('Você já possui uma viatura retirada em seu nome. É necessário realizar a devolução dela antes de retirar outra!'),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return; 
                                }
                              }

                              String? placaExtraida = await _ocrService.lerPlacaDaCamera();

                              if (placaExtraida != null) {
                                try {
                                  if (moduleName == 'Entrada de Viatura') {
                                    var movimentacaoAtiva = await ApiService.verificarSaidaAtiva(placaExtraida);
                                    
                                    if (movimentacaoAtiva == null) {
                                      setStateModal(() {
                                        isLoadingVeiculo = false;
                                      });
                                      if (!context.mounted) return;
                                      
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Ação Bloqueada'),
                                          content: Text('A viatura de placa $placaExtraida não possui registro de saída pendente para ser devolvida!'),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                      );
                                      return; 
                                    }
                                  }

                                  final veiculo = await ApiService.buscarVeiculoPorPlaca(placaExtraida);
                                  
                                  fotoPlacaTirada = true;
                                  placaLida = veiculo['placa'] ?? placaExtraida;
                                  modeloLido = veiculo['modelo'] ?? 'Modelo não informado';
                                  corLida = veiculo['cor'] ?? 'Cor não informada';
                                  isLoadingVeiculo = false;
                                  atualizarObservacoesAutomaticas(setStateModal);
                                } catch (e) {
                                  fotoPlacaTirada = true;
                                  placaLida = placaExtraida;
                                  modeloLido = 'Veículo não cadastrado';
                                  corLida = '-';
                                  isLoadingVeiculo = false;
                                  atualizarObservacoesAutomaticas(setStateModal);
                                }
                              } else {
                                setStateModal(() {
                                  isLoadingVeiculo = false;
                                });
                              }

                              if (!context.mounted) return;
                              if (fotoPlacaTirada) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Placa lida: $placaLida')),
                                );
                              }
                            },
                            icon: isLoadingVeiculo 
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.camera_alt, color: fotoPlacaTirada ? Colors.green : null),
                            label: Text(
                              fotoPlacaTirada ? 'Placa OK' : 'Foto Placa',
                              style: TextStyle(
                                color: fotoPlacaTirada ? Colors.green : null,
                                fontWeight: fotoPlacaTirada ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: fotoPlacaTirada ? Colors.green : Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              String? kmExtraido = await _ocrService.lerKmDoPainel();

                              if (kmExtraido != null) {
                                fotoPainelTirada = true;
                                kmLido = kmExtraido;
                                atualizarObservacoesAutomaticas(setStateModal);

                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Painel lido: $kmLido')),
                                );
                              }
                            },
                            icon: Icon(Icons.photo_camera, color: fotoPainelTirada ? Colors.green : null),
                            label: Text(
                              fotoPainelTirada ? 'Painel OK' : 'Foto Painel',
                              style: TextStyle(
                                color: fotoPainelTirada ? Colors.green : null,
                                fontWeight: fotoPainelTirada ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: fotoPainelTirada ? Colors.green : Colors.grey),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: observationController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Observações / Dados Tratados',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _ocrService.dispose();
                Navigator.pop(context);
              },
              child: const Text('Fechar'),
            ),
            ElevatedButton(
              onPressed: (hasPhotoFeature && (!fotoPlacaTirada || !fotoPainelTirada)) 
                ? null 
                : () async {
                    String obsFinal = observationController.text.trim();

                    Provider.of<LogProvider>(context, listen: false).addLog(
                      agentName: nome,
                      actionType: moduleName,
                      observations: obsFinal.isEmpty ? 'Nenhuma observação informada.' : obsFinal,
                    );

                    try {
                      await ApiService.registrarMovimentacao({
                        'agente_nome': nome,
                        'tipo_movimento': moduleName,
                        'placa': placaLida.isNotEmpty ? placaLida : 'N/A',
                        'modelo': '$modeloLido ($corLida)',
                        'quilometragem': kmLido.isNotEmpty ? kmLido : 'N/A',
                        'observacoes': obsFinal,
                      });
                    } catch (e) {
                      print('Erro ao enviar para o banco: $e');
                    }

                    _ocrService.dispose();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Movimentação registrada e salva no banco de dados com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  // Modal de Cadastro de Viaturas
  void _abrirModalGestaoViaturas(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    final _placaController = TextEditingController();
    final _modeloController = TextEditingController();
    
    final List<String> _listaCores = ['Branco', 'Prata', 'Preto', 'Cinza', 'Vermelho', 'Azul'];
    final List<String> _listaModelos = [
      'Fiat Toro', 'Fiat Argo', 'Fiat Strada', 'Fiat Cronos',
      'Volkswagen Polo', 'Renault Duster', 'Renault Oroch',
      'Chevrolet Trailblazer', 'Chevrolet S10', 'Toyota Hilux',
      'Mitsubishi L200', 'Ford Ranger'
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
            height: 520,
            child: Column(
              children: [
                ExpansionTile(
                  title: const Text('Cadastrar Nova Viatura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _placaController,
                              decoration: const InputDecoration(labelText: 'Placa (Ex: ABC-1234)', border: OutlineInputBorder()),
                              validator: (v) => v!.isEmpty ? 'Informe a placa' : null,
                            ),
                            const SizedBox(height: 8),
                            Autocomplete<String>(
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<String>.empty();
                                }
                                return _listaModelos.where((String modelo) {
                                  return modelo.toLowerCase().contains(textEditingValue.text.toLowerCase());
                                });
                              },
                              onSelected: (String selection) {
                                _modeloController.text = selection;
                              },
                              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                                if (_modeloController.text.isNotEmpty && controller.text.isEmpty) {
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
                                    helperText: 'Digite para filtrar ou ver sugestões',
                                  ),
                                  validator: (v) => _modeloController.text.isEmpty ? 'Informe o modelo' : null,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _corSelecionada,
                              decoration: const InputDecoration(labelText: 'Cor', border: OutlineInputBorder()),
                              hint: const Text('Selecione a cor'),
                              items: _listaCores.map((String cor) {
                                return DropdownMenuItem<String>(
                                  value: cor,
                                  child: Text(cor),
                                );
                              }).toList(),
                              validator: (v) => v == null ? 'Selecione a cor' : null,
                              onChanged: (val) => setStateModal(() => _corSelecionada = val),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800),
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: const Text('Salvar Viatura', style: TextStyle(color: Colors.white)),
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  bool sucesso = await ApiService.cadastrarViatura({
                                    'placa': _placaController.text.toUpperCase(),
                                    'modelo': _modeloController.text,
                                    'cor': _corSelecionada!,
                                    'status': 'disponivel',
                                  });

                                  if (sucesso) {
                                    _placaController.clear();
                                    _modeloController.clear();
                                    _corSelecionada = null;
                                    setStateModal(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Viatura cadastrada com sucesso!'), backgroundColor: Colors.green),
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
                const Text('Viaturas Cadastradas no Sistema', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: ApiService.listarTodasViaturas(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('Nenhuma viatura cadastrada.'));
                      }

                      final veiculos = snapshot.data!;
                      return ListView.builder(
                        itemCount: veiculos.length,
                        itemBuilder: (context, index) {
                          final v = veiculos[index];
                          bool isDisponivel = (v['status'] ?? 'disponivel') == 'disponivel';

                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.directions_car, color: isDisponivel ? Colors.green : Colors.red),
                              title: Text('${v['placa']} - ${v['modelo']}'),
                              subtitle: Text('Cor: ${v['cor']} | Status: ${v['status']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isDisponivel ? Icons.toggle_on : Icons.toggle_off,
                                      color: isDisponivel ? Colors.green : Colors.grey,
                                      size: 30,
                                    ),
                                    tooltip: 'Alternar Status',
                                    onPressed: () async {
                                      String novoStatus = isDisponivel ? 'indisponivel' : 'disponivel';
                                      bool atualizado = await ApiService.atualizarViatura(v['id'], {
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
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Excluir Viatura',
                                    onPressed: () async {
                                      bool deletou = await ApiService.excluirViatura(v['id']);
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

  void _abrirModalInfracoes(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    final _numeroController = TextEditingController();
    final _placaController = TextEditingController();
    final _localController = TextEditingController();
    final _dataHoraController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                    decoration: const InputDecoration(labelText: 'Número da Infração / Auto', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Informe o número' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _placaController,
                    decoration: const InputDecoration(labelText: 'Placa da Viatura', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Informe a placa' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _localController,
                    decoration: const InputDecoration(labelText: 'Local da Infração', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Informe o local' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _dataHoraController,
                    decoration: const InputDecoration(labelText: 'Data e Hora (Ex: 23/07/2026 14:30)', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Informe a data e hora' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                final sucesso = await ApiService.registrarInfracao(
                  numeroAuto: _numeroController.text,
                  placaViatura: _placaController.text,
                  local: _localController.text,
                  dataHora: _dataHoraController.text,
                  agenteResponsavel: nome,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(sucesso ? 'Infração salva com sucesso!' : 'Erro ao comunicar com o servidor.'),
                    backgroundColor: sucesso ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Processar e Vincular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showHistoryScreen(BuildContext context) {
    DateTime? dataInicio;
    DateTime? dataFim;

    // Carrega os dados da API ao abrir o modal
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.carregarMovimentacoes(agente: isAdm ? null : nome);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.history, color: isAdm ? const Color(0xFF0F172A) : Colors.blue.shade800),
              const SizedBox(width: 8),
              Text(isAdm ? 'Histórico / Auditoria Completa' : 'Meu Histórico de Movimentações'),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 500,
            child: Column(
              children: [
                // Filtros de Data
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
                          label: Text(dataInicio == null ? 'Data Início' : '${dataInicio!.day}/${dataInicio!.month}/${dataInicio!.year}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dataInicio ?? DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setStateModal(() => dataInicio = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(dataFim == null ? 'Data Fim' : '${dataFim!.day}/${dataFim!.month}/${dataFim!.year}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dataFim ?? DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setStateModal(() => dataFim = picked);
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

                      // Se não for admin, filtra rigorosamente apenas os logs do próprio usuário logado
                      var logsFiltrados = isAdm 
                          ? logProvider.logs 
                          : logProvider.logs.where((l) => l.agentName.toLowerCase() == nome.toLowerCase()).toList();

                      // Aplicação do Filtro de Data (caso selecionado)
                      if (dataInicio != null) {
                        logsFiltrados = logsFiltrados.where((l) {
                          return l.timestamp.isAfter(dataInicio!.subtract(const Duration(days: 1)));
                        }).toList();
                      }
                      if (dataFim != null) {
                        logsFiltrados = logsFiltrados.where((l) {
                          return l.timestamp.isBefore(dataFim!.add(const Duration(days: 1)));
                        }).toList();
                      }

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
                              : log.actionType.contains('Entrada') 
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
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(log.actionType, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: corAcao)),
                                      Text(
                                        '${log.timestamp.day.toString().padLeft(2, '0')}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.year} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Text('Agente: ${log.agentName}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                  if (log.placa.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('Placa: ${log.placa} | Modelo: ${log.modelo}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                  if (log.quilometragem != null) ...[
                                    const SizedBox(height: 2),
                                    Text('KM: ${log.quilometragem}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text('Detalhes / Observações: ${log.observations}'),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.share, color: Colors.white),
              label: const Text('Enviar WhatsApp', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                final logProvider = Provider.of<LogProvider>(context, listen: false);
                var logsParaEnvio = isAdm 
                    ? logProvider.logs 
                    : logProvider.logs.where((l) => l.agentName.toLowerCase() == nome.toLowerCase()).toList();

                if (logsParaEnvio.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não há registros para exportar.'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                String textoMensagem = "*RELATÓRIO DE MOVIMENTAÇÃO - SGV PCPE*\n";
                textoMensagem += "Usuário: $nome\n\n";

                for (var l in logsParaEnvio) {
                  textoMensagem += "• *${l.actionType}*\n";
                  textoMensagem += "  Data: ${l.timestamp.toString().substring(0, 16)}\n";
                  if (l.placa.isNotEmpty) textoMensagem += "  Placa: ${l.placa}\n";
                  textoMensagem += "  Info: ${l.observations}\n\n";
                }

                final encodedUrl = Uri.encodeFull("https://wa.me/?text=$textoMensagem");
                if (await canLaunchUrl(Uri.parse(encodedUrl))) {
                  await launchUrl(Uri.parse(encodedUrl), mode: LaunchMode.externalApplication);
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o WhatsApp.'), backgroundColor: Colors.red),
                  );
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

  @override
  Widget build(BuildContext context) {
    // Módulos padrão para qualquer usuário logado (incluindo o Histórico individual)
    final List<Widget> modulosPermitidos = [
      _buildModuleCard(context, 'Saída de Viatura', Icons.exit_to_app, Colors.blue.shade800, true, () => _showModuleScreen(context, 'Saída de Viatura', true)),
      _buildModuleCard(context, 'Entrada de Viatura', Icons.login, Colors.green.shade800, true, () => _showModuleScreen(context, 'Entrada de Viatura', true)),
      _buildModuleCard(context, 'Meu Histórico', Icons.history, Colors.indigo.shade700, false, () => _showHistoryScreen(context)),
    ];

    // Se for Administrador, adiciona os módulos administrativos e substitui o histórico por visão global
    if (isAdm) {
      modulosPermitidos.addAll([
        _buildModuleCard(context, 'Cadastro de Viaturas', Icons.directions_car, Colors.teal.shade800, false, () => _abrirModalGestaoViaturas(context)),
        _buildModuleCard(context, 'Gestão de Infrações', Icons.gavel, Colors.orange.shade800, false, () => _abrirModalInfracoes(context)),
        _buildModuleCard(context, 'Manutenção', Icons.build, Colors.red.shade800, false, () => _showModuleScreen(context, 'Manutenção', false)),
      ]);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: const [
            Icon(Icons.local_police, color: Colors.white),
            SizedBox(width: 12),
            Text('SGV - Polícia Civil de Pernambuco', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                '$cargo: $nome ${isAdm ? '(ADM)' : ''}',
                style: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bem-vindo, $nome', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      if (isAdm)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
                          child: const Text('ADMINISTRADOR', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Cargo: $cargo', style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('CPF: $cpf | E-mail: $email', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Login efetuado em: $horaLogin', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Módulos Operacionais', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.8,
              ),
              itemCount: modulosPermitidos.length,
              itemBuilder: (context, index) => modulosPermitidos[index],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleCard(BuildContext context, String title, IconData icon, Color color, bool isPrimary, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}