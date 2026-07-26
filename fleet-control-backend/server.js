const express = require('express');
const cors = require('cors');
const pool = require('./db');
require('dotenv').config();

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 3000;

// ==========================================
// CRIAÇÃO / MIGRAÇÃO DE TABELAS
// ==========================================

pool.query(`
  CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    cpf VARCHAR(14) UNIQUE NOT NULL,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    criado_em TIMESTAMP DEFAULT NOW()
  );
`).catch(err => console.error('Erro ao criar tabela usuarios:', err));

pool.query(`ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS cargo VARCHAR(100) DEFAULT 'Agente'`)
  .catch(err => console.error('Erro ao adicionar coluna cargo:', err));
pool.query(`ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS is_adm BOOLEAN DEFAULT false`)
  .catch(err => console.error('Erro ao adicionar coluna is_adm:', err));
pool.query(`ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS senha VARCHAR(255) DEFAULT '123456'`)
  .catch(err => console.error('Erro ao adicionar coluna senha:', err));
pool.query(`ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS atualizado_em TIMESTAMP DEFAULT NOW()`)
  .catch(err => console.error('Erro ao adicionar coluna atualizado_em:', err));

pool.query(`UPDATE usuarios SET cargo = 'Agente' WHERE cargo IS NULL`)
  .catch(err => console.error('Erro ao preencher cargos nulos:', err));
pool.query(`UPDATE usuarios SET senha = '123456' WHERE senha IS NULL`)
  .catch(err => console.error('Erro ao preencher senhas nulas:', err));

pool.query(`
  INSERT INTO usuarios (cpf, nome, email, cargo, is_adm, senha)
  VALUES ('00000000191', 'Delegado Titular', 'delegado@policiacivil.pe.gov.br', 'Delegado', true, 'admin123')
  ON CONFLICT (cpf) DO NOTHING;
`).catch(err => console.error('Erro ao inserir seed de admin:', err));

pool.query(`
  INSERT INTO usuarios (cpf, nome, email, cargo, is_adm, senha)
  VALUES ('06611289461', 'Fabio Fernandes dos Santos', 'fabiofernandes@policiacivil.pe.gov.br', 'Agente', true, '123456')
  ON CONFLICT (cpf) DO UPDATE SET cargo = 'Agente', is_adm = true, senha = '123456';
`).catch(err => console.error('Erro ao inserir seed de fabiofernandes:', err));

pool.query(`
  CREATE TABLE IF NOT EXISTS viaturas (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(10) UNIQUE NOT NULL,
    modelo VARCHAR(255),
    cor VARCHAR(100),
    status VARCHAR(50) DEFAULT 'disponivel',
    quilometragem_inicial INTEGER DEFAULT 0,
    criado_em TIMESTAMP DEFAULT NOW()
  );
`).catch(err => console.error('Erro ao criar tabela viaturas:', err));

pool.query(`ALTER TABLE viaturas ADD COLUMN IF NOT EXISTS quilometragem_inicial INTEGER DEFAULT 0`)
  .catch(err => console.error('Erro ao adicionar coluna quilometragem_inicial:', err));

// ==========================================
// CORREÇÃO DE KM INICIAL: Garante que TODAS as viaturas tenham KM > 0
// ==========================================
const corrigirKmInicial = async () => {
  try {
    // Atualiza viaturas com KM nulo ou zero para valores padrão por modelo
    const semKm = await pool.query(
      `SELECT id, placa, modelo, quilometragem_inicial FROM viaturas WHERE quilometragem_inicial IS NULL OR quilometragem_inicial = 0`
    );
    if (semKm.rows.length > 0) {
      console.log(`Encontradas ${semKm.rows.length} viaturas sem KM inicial. Corrigindo...`);
      for (const v of semKm.rows) {
        // Define um KM padrão baseado no modelo, ou 10000 como fallback
        let kmPadrao = 10000;
        const modeloLower = (v.modelo || '').toLowerCase();
        if (modeloLower.includes('hilux') || modeloLower.includes('l200') || modeloLower.includes('ranger') || modeloLower.includes('s10') || modeloLower.includes('trailblazer')) kmPadrao = 50000;
        else if (modeloLower.includes('toro') || modeloLower.includes('duster') || modeloLower.includes('oroch')) kmPadrao = 35000;
        else if (modeloLower.includes('argo') || modeloLower.includes('polo') || modeloLower.includes('cronos') || modeloLower.includes('strada')) kmPadrao = 15000;

        await pool.query('UPDATE viaturas SET quilometragem_inicial = $1 WHERE id = $2', [kmPadrao, v.id]);
        console.log(`  ✅ Viatura ${v.placa} (${v.modelo || 'sem modelo'}): KM definido para ${kmPadrao}`);
      }
    } else {
      console.log('Todas as viaturas já possuem KM inicial válido.');
    }
  } catch (err) {
    console.error('Erro ao corrigir KM inicial das viaturas:', err);
  }
};

pool.query(`
  CREATE TABLE IF NOT EXISTS manutencoes (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(10) NOT NULL,
    componente VARCHAR(255) NOT NULL,
    km_limite INTEGER NOT NULL,
    km_atual INTEGER NOT NULL,
    status VARCHAR(50) DEFAULT 'pendente',
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_baixa TIMESTAMP,
    baixado_por VARCHAR(255)
  );
`).catch(err => console.error('Erro ao criar tabela manutencoes:', err));

app.get('/', (req, res) => {
  res.json({ status: 'API do SGV-Viaturas online!' });
});

// ==========================================
// ROTAS DE MOVIMENTAÇÃO E HISTÓRICO
// ==========================================

app.post('/api/movimentacoes', async (req, res) => {
  const { agente_nome, tipo_movimento, placa, modelo, quilometragem, observacoes } = req.body;
  const km = (quilometragem !== undefined && quilometragem !== null && quilometragem !== '' && quilometragem !== 'N/A' && !isNaN(Number(quilometragem)))
    ? Number(quilometragem) : null;
  try {
    const ultimoLogQuery = `SELECT * FROM vehicle_logs WHERE placa = $1 ORDER BY id DESC LIMIT 1;`;
    const ultimoLogResult = await pool.query(ultimoLogQuery, [placa.toUpperCase()]);
    const ultimoLog = ultimoLogResult.rows.length > 0 ? ultimoLogResult.rows[0] : null;
    const viaturaEmUso = ultimoLog && ultimoLog.tipo_movimento === 'Saída de Viatura';

    // ==========================================
    // VALIDAÇÃO DE KM MÍNIMO
    // ==========================================
    if (km !== null) {
      if (tipo_movimento === 'Saída de Viatura') {
        // KM da saída não pode ser menor que o KM inicial do cadastro
        const viaturaResult = await pool.query('SELECT quilometragem_inicial FROM viaturas WHERE placa = $1', [placa.toUpperCase()]);
        if (viaturaResult.rows.length > 0) {
          const kmInicial = viaturaResult.rows[0].quilometragem_inicial || 0;
          if (km < kmInicial) {
            return res.status(409).json({
              erro: 'KM inválido',
              mensagem: `A quilometragem informada (${km} km) é menor que a quilometragem inicial de cadastro da viatura (${kmInicial} km). Corrija o valor e tente novamente.`,
              km_minimo_permitido: kmInicial,
            });
          }
        }
      }

      if (tipo_movimento === 'Devolução de Viatura') {
        // KM da devolução não pode ser menor que o KM da saída
        const saidaQuery = `SELECT quilometragem FROM vehicle_logs WHERE placa = $1 AND tipo_movimento = 'Saída de Viatura' ORDER BY id DESC LIMIT 1;`;
        const saidaResult = await pool.query(saidaQuery, [placa.toUpperCase()]);
        if (saidaResult.rows.length > 0 && saidaResult.rows[0].quilometragem !== null) {
          const kmSaida = saidaResult.rows[0].quilometragem;
          if (km < kmSaida) {
            return res.status(409).json({
              erro: 'KM inválido',
              mensagem: `A quilometragem informada (${km} km) é menor que a quilometragem registrada na saída (${kmSaida} km). A devolução não pode ter KM inferior ao da retirada.`,
              km_minimo_permitido: kmSaida,
            });
          }
        }
      }
    }
    // ==========================================

    if (tipo_movimento === 'Saída de Viatura') {
      if (viaturaEmUso) {
        return res.status(409).json({ erro: 'Viatura já em uso', mensagem: `A viatura de placa ${placa} já se encontra em uso/fora da base. Não é possível gerar uma nova saída.` });
      }
      const agenteAtivoQuery = `SELECT * FROM vehicle_logs WHERE LOWER(agent_name) = LOWER($1) ORDER BY id DESC LIMIT 1;`;
      const agenteAtivoResult = await pool.query(agenteAtivoQuery, [agente_nome]);
      if (agenteAtivoResult.rows.length > 0 && agenteAtivoResult.rows[0].tipo_movimento === 'Saída de Viatura') {
        return res.status(409).json({ erro: 'Agente já possui viatura em uso', mensagem: `O agente ${agente_nome} já possui uma viatura retirada. É necessário realizar a devolução antes de retirar outra.` });
      }
    }
    if (tipo_movimento === 'Devolução de Viatura') {
      if (!viaturaEmUso) {
        return res.status(409).json({ erro: 'Viatura não está em uso', mensagem: `A viatura de placa ${placa} não possui registro de saída ativo. Não é possível realizar a devolução.` });
      }
    }
    const query = `INSERT INTO vehicle_logs (agent_name, action_type, agente_nome, tipo_movimento, placa, modelo, quilometragem, observations, data_hora_saida) VALUES ($1, $2, $1, $2, $3, $4, $5, $6, NOW()) RETURNING *;`;
    const values = [agente_nome, tipo_movimento, placa, modelo, km, observacoes];
    const novoLog = await pool.query(query, values);
    try {
      if (tipo_movimento === 'Saída de Viatura') {
        await pool.query('UPDATE viaturas SET status = $1 WHERE placa = $2', ['indisponivel', placa.toUpperCase()]);
      } else if (tipo_movimento === 'Devolução de Viatura') {
        await pool.query('UPDATE viaturas SET status = $1 WHERE placa = $2', ['disponivel', placa.toUpperCase()]);
      }
    } catch (updateErr) { console.error('Erro ao atualizar status da viatura:', updateErr); }
    if (km !== null) { await verificarManutencaoAutomatica(placa.toUpperCase(), km); }
    res.status(201).json({ mensagem: 'Movimentação registrada com sucesso!', movimentacao: novoLog.rows[0] });
  } catch (err) {
    console.error('Erro ao registrar movimentação:', err);
    res.status(500).json({ erro: 'Erro interno ao registrar movimentação.' });
  }
});

app.get('/api/movimentacoes', async (req, res) => {
  const { agente } = req.query;
  try {
    let query = 'SELECT * FROM vehicle_logs';
    let values = [];
    if (agente) { query += ' WHERE LOWER(agent_name) = LOWER($1)'; values.push(agente); }
    query += ' ORDER BY id DESC';
    const resultado = await pool.query(query, values);
    res.json(resultado.rows);
  } catch (err) { console.error('Erro ao buscar histórico:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

app.get('/api/movimentacoes/usuario-ativo/:nome', async (req, res) => {
  const { nome } = req.params;
  try {
    const resultado = await pool.query(`SELECT * FROM vehicle_logs WHERE LOWER(agent_name) = LOWER($1) ORDER BY id DESC LIMIT 1;`, [nome]);
    if (resultado.rows.length > 0 && resultado.rows[0].action_type === 'Saída de Viatura') return res.json({ ativo: true, dados: resultado.rows[0] });
    res.json({ ativo: false });
  } catch (err) { console.error('Erro:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

app.get('/api/movimentacoes/saida-ativa/:placa', async (req, res) => {
  const { placa } = req.params;
  try {
    const resultado = await pool.query(`SELECT * FROM vehicle_logs WHERE placa = $1 ORDER BY id DESC LIMIT 1;`, [placa.toUpperCase()]);
    if (resultado.rows.length > 0 && resultado.rows[0].action_type === 'Saída de Viatura') return res.json({ encontrada: true, dados: resultado.rows[0] });
    res.json({ encontrada: false });
  } catch (err) { console.error('Erro:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

async function verificarManutencaoAutomatica(placa, kmAtual) {
  try {
    const viaturaResult = await pool.query('SELECT * FROM viaturas WHERE placa = $1', [placa]);
    if (viaturaResult.rows.length === 0) return;
    const kmInicial = viaturaResult.rows[0].quilometragem_inicial || 0;
    const componentes = [
      { nome: 'Troca de Óleo e Filtro', km_limite: 10000 },
      { nome: 'Filtro de Ar', km_limite: 15000 },
      { nome: 'Filtro de Combustível', km_limite: 20000 },
      { nome: 'Pastilhas de Freio', km_limite: 25000 },
      { nome: 'Discos de Freio', km_limite: 30000 },
      { nome: 'Correia Dentada', km_limite: 55000 },
    ];
    for (const comp of componentes) {
      const existente = await pool.query(`SELECT id, status FROM manutencoes WHERE placa = $1 AND componente = $2 AND status = 'pendente' ORDER BY id DESC LIMIT 1`, [placa, comp.nome]);
      if (kmAtual >= kmInicial + comp.km_limite && existente.rows.length === 0) {
        await pool.query(`INSERT INTO manutencoes (placa, componente, km_limite, km_atual, status) VALUES ($1, $2, $3, $4, 'pendente')`, [placa, comp.nome, kmInicial + comp.km_limite, kmAtual]);
      }
    }
  } catch (err) { console.error('Erro na verificação automática de manutenção:', err); }
}

// ==========================================
// ROTAS DE VIATURAS
// ==========================================
app.post('/api/viaturas', async (req, res) => {
  const { placa, modelo, cor, status, quilometragem_inicial } = req.body;
  try {
    const kmInicial = quilometragem_inicial !== undefined && quilometragem_inicial !== null ? Number(quilometragem_inicial) : 0;
    const novaViatura = await pool.query(`INSERT INTO viaturas (placa, modelo, cor, status, quilometragem_inicial) VALUES ($1, $2, $3, $4, $5) RETURNING *;`, [placa.toUpperCase(), modelo, cor, status || 'disponivel', kmInicial]);
    if (kmInicial > 0) await verificarManutencaoAutomatica(placa.toUpperCase(), kmInicial);
    res.status(201).json(novaViatura.rows[0]);
  } catch (err) { console.error('Erro:', err); res.status(500).json({ erro: 'Erro ao cadastrar viatura.' }); }
});

app.get('/api/viaturas', async (req, res) => {
  try { const r = await pool.query('SELECT * FROM viaturas ORDER BY id DESC'); res.json(r.rows); }
  catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// Retorna o último KM registrado para uma viatura (histórico ou cadastro inicial)
// ⚠️ Esta rota DEVE vir ANTES de /api/viaturas/:placa para não ser capturada por ela
app.get('/api/viaturas/:placa/ultimo-km', async (req, res) => {
  const { placa } = req.params;
  try {
    const placaUpper = placa.toUpperCase();
    // Busca o último registro no histórico que tenha quilometragem
    const ultimoLog = await pool.query(
      `SELECT quilometragem, tipo_movimento, data_hora_saida FROM vehicle_logs 
       WHERE placa = $1 AND quilometragem IS NOT NULL 
       ORDER BY id DESC LIMIT 1`,
      [placaUpper]
    );
    if (ultimoLog.rows.length > 0 && ultimoLog.rows[0].quilometragem !== null) {
      return res.json({
        ultimo_km: ultimoLog.rows[0].quilometragem,
        origem: ultimoLog.rows[0].tipo_movimento,
        data: ultimoLog.rows[0].data_hora_saida,
      });
    }
    // Fallback: KM inicial do cadastro
    const viatura = await pool.query('SELECT quilometragem_inicial FROM viaturas WHERE placa = $1', [placaUpper]);
    if (viatura.rows.length > 0) {
      return res.json({
        ultimo_km: viatura.rows[0].quilometragem_inicial || 0,
        origem: 'Cadastro inicial',
        data: null,
      });
    }
    return res.status(404).json({ erro: 'Viatura não encontrada.' });
  } catch (err) { console.error('Erro em /ultimo-km:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

app.get('/api/viaturas/:placa', async (req, res) => {
  const { placa } = req.params;
  try {
    const r = await pool.query('SELECT * FROM viaturas WHERE placa = $1', [placa.toUpperCase()]);
    if (r.rows.length === 0) return res.status(404).json({ erro: 'Viatura não encontrada.' });
    res.json(r.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro interno.' }); }
});

app.put('/api/viaturas/:id', async (req, res) => {
  const { id } = req.params;
  const { placa, modelo, cor, status, quilometragem_inicial } = req.body;
  try {
    const r = await pool.query(`UPDATE viaturas SET placa = $1, modelo = $2, cor = $3, status = $4, quilometragem_inicial = COALESCE($5, quilometragem_inicial) WHERE id = $6 RETURNING *;`, [placa.toUpperCase(), modelo, cor, status, quilometragem_inicial, id]);
    res.json(r.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.delete('/api/viaturas/:id', async (req, res) => {
  try { await pool.query('DELETE FROM viaturas WHERE id = $1', [req.params.id]); res.json({ mensagem: 'Viatura excluída.' }); }
  catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// ==========================================
// ROTAS DE MANUTENÇÃO
// ==========================================
app.get('/api/manutencoes/alertas/:placa', async (req, res) => {
  try {
    // DISTINCT ON garante apenas um registro por componente (o mais recente)
    const r = await pool.query(
      `SELECT DISTINCT ON (componente) * FROM manutencoes WHERE placa = $1 AND status = 'pendente' ORDER BY componente, id DESC`,
      [req.params.placa.toUpperCase()]
    );
    res.json({ alertas: r.rows });
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.get('/api/manutencoes', async (req, res) => {
  try {
    const r = await pool.query(
      `SELECT DISTINCT ON (m.placa, m.componente) m.*, v.modelo, v.quilometragem_inicial 
       FROM manutencoes m LEFT JOIN viaturas v ON v.placa = m.placa 
       WHERE m.status = 'pendente' ORDER BY m.placa, m.componente, m.id DESC`
    );
    res.json(r.rows);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.put('/api/manutencoes/:id/baixa', async (req, res) => {
  const { baixado_por, baixar_todas, placa, componente } = req.body;
  try {
    if (baixar_todas && placa) {
      await pool.query(`UPDATE manutencoes SET status = 'concluido', data_baixa = NOW(), baixado_por = $1 WHERE placa = $2 AND status = 'pendente'`, [baixado_por, placa.toUpperCase()]);
      return res.json({ mensagem: 'Todas as manutenções foram baixadas.' });
    } else if (componente && placa) {
      await pool.query(`UPDATE manutencoes SET status = 'concluido', data_baixa = NOW(), baixado_por = $1 WHERE placa = $2 AND componente = $3 AND status = 'pendente'`, [baixado_por, placa.toUpperCase(), componente]);
      return res.json({ mensagem: `Manutenção de "${componente}" baixada.` });
    } else {
      await pool.query(`UPDATE manutencoes SET status = 'concluido', data_baixa = NOW(), baixado_por = $1 WHERE id = $2`, [baixado_por, req.params.id]);
      return res.json({ mensagem: 'Manutenção baixada.' });
    }
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.post('/api/manutencoes/recalcular/:placa', async (req, res) => {
  try {
    const ultimoKm = await pool.query(`SELECT quilometragem FROM vehicle_logs WHERE placa = $1 AND quilometragem IS NOT NULL ORDER BY id DESC LIMIT 1`, [req.params.placa.toUpperCase()]);
    if (ultimoKm.rows.length > 0) await verificarManutencaoAutomatica(req.params.placa.toUpperCase(), ultimoKm.rows[0].quilometragem);
    const alertas = await pool.query(`SELECT * FROM manutencoes WHERE placa = $1 AND status = 'pendente' ORDER BY componente`, [req.params.placa.toUpperCase()]);
    res.json({ mensagem: 'Manutenções recalculadas.', alertas: alertas.rows });
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// ==========================================
// INFRAÇÕES
// ==========================================
pool.query(`CREATE TABLE IF NOT EXISTS infracoes (id SERIAL PRIMARY KEY, numero_auto TEXT NOT NULL, placa_viatura TEXT NOT NULL, local TEXT, data_hora TIMESTAMP, agente_responsavel TEXT, motorista_identificado TEXT, criado_em TIMESTAMP DEFAULT NOW());`).catch(err => console.error(err));

app.post('/api/infracoes/processar', async (req, res) => {
  const { numero_auto, placa_viatura, local, data_hora, agente_responsavel } = req.body;
  if (!numero_auto || !placa_viatura || !data_hora) return res.status(400).json({ erro: 'Campos obrigatórios.' });
  try {
    let dataHoraInfracao;
    const parsed = new Date(data_hora);
    if (!isNaN(parsed.getTime())) { dataHoraInfracao = parsed.toISOString(); }
    else {
      const brMatch = data_hora.match(/(\d{2})\/(\d{2})\/(\d{4})\s*(\d{2}):?(\d{2})?/);
      if (brMatch) { const [, d, m, y, h = '00', min = '00'] = brMatch; dataHoraInfracao = new Date(`${y}-${m}-${d}T${h}:${min}:00`).toISOString(); }
      else return res.status(400).json({ erro: 'Formato de data inválido.' });
    }
    const placa = placa_viatura.toUpperCase().trim();
    const ultimoLogResult = await pool.query(`SELECT * FROM vehicle_logs WHERE placa = $1 AND data_hora_saida <= $2 ORDER BY data_hora_saida DESC, id DESC LIMIT 1;`, [placa, dataHoraInfracao]);
    const ultimoLog = ultimoLogResult.rows.length > 0 ? ultimoLogResult.rows[0] : null;
    let motoristaEncontrado = null, mensagemCruzamento = '';
    if (!ultimoLog) mensagemCruzamento = `Nenhum registro de movimentação encontrado.`;
    else if (ultimoLog.tipo_movimento === 'Devolução de Viatura') mensagemCruzamento = `Viatura devolvida antes da infração.`;
    else if (ultimoLog.tipo_movimento === 'Saída de Viatura') { motoristaEncontrado = { agent_name: ultimoLog.agent_name || ultimoLog.agente_nome, placa: ultimoLog.placa, modelo: ultimoLog.modelo, data_hora_saida: ultimoLog.data_hora_saida, quilometragem: ultimoLog.quilometragem, id_log: ultimoLog.id }; mensagemCruzamento = 'Agente identificado.'; }
    else mensagemCruzamento = 'Registro sem condutor identificado.';
    const novaInfracao = await pool.query(`INSERT INTO infracoes (numero_auto, placa_viatura, local, data_hora, agente_responsavel, motorista_identificado) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *;`, [numero_auto, placa, local, dataHoraInfracao, agente_responsavel || '', motoristaEncontrado ? motoristaEncontrado.agent_name : null]);

    // Gera notificação para o ADM (Delegado Titular) sobre a nova infração
    try {
      const tituloNotif = motoristaEncontrado
        ? `Infração Vinculada - Auto ${numero_auto}`
        : `Infração Registrada - Auto ${numero_auto}`;
      const mensagemNotif = motoristaEncontrado
        ? `Auto ${numero_auto} - placa ${placa} em ${data_hora || ''}. Responsável: ${motoristaEncontrado.agent_name}. Local: ${local || 'Não informado'}.`
        : `Auto ${numero_auto} - placa ${placa} em ${data_hora || ''}. Nenhum condutor identificado. Local: ${local || 'Não informado'}.`;

      // Notifica o Delegado Titular (CPF 00000000191) sobre TODAS as infrações
      await pool.query(
        `INSERT INTO notificacoes (cpf_usuario, tipo, titulo, mensagem, placa, data_ocorrencia) VALUES ($1, 'multa', $2, $3, $4, NOW())`,
        ['00000000191', tituloNotif, mensagemNotif, placa]
      );

      // Se identificou motorista, notifica também o agente responsável
      if (motoristaEncontrado && motoristaEncontrado.agent_name) {
        // Busca CPF do agente pelo nome
        const agenteResult = await pool.query(
          'SELECT cpf FROM usuarios WHERE LOWER(nome) = LOWER($1) LIMIT 1',
          [motoristaEncontrado.agent_name]
        );
        if (agenteResult.rows.length > 0) {
          await pool.query(
            `INSERT INTO notificacoes (cpf_usuario, tipo, titulo, mensagem, placa, data_ocorrencia) VALUES ($1, 'multa', $2, $3, $4, NOW())`,
            [agenteResult.rows[0].cpf, tituloNotif, mensagemNotif, placa]
          );
        }
      }
    } catch (notifErr) {
      console.error('Erro ao gerar notificação de infração:', notifErr);
    }

    res.status(201).json({ mensagem: motoristaEncontrado ? 'Infração processada! Responsável identificado.' : 'Infração registrada.', infracao: novaInfracao.rows[0], motorista: motoristaEncontrado, encontrado: motoristaEncontrado !== null, detalhes_cruzamento: mensagemCruzamento });
  } catch (err) { console.error('Erro:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

// Endpoint para buscar infrações por placa da viatura
app.get('/api/infracoes/busca/:placa', async (req, res) => {
  try {
    const r = await pool.query(
      `SELECT i.*, v.modelo, v.cor FROM infracoes i LEFT JOIN viaturas v ON UPPER(v.placa) = UPPER(i.placa_viatura) WHERE UPPER(i.placa_viatura) = $1 ORDER BY i.criado_em DESC`,
      [req.params.placa.toUpperCase()]
    );
    res.json(r.rows);
  } catch (err) { console.error('Erro ao buscar infrações por placa:', err); res.status(500).json({ erro: 'Erro interno.' }); }
});

// ==========================================
// USUÁRIOS
// ==========================================
app.post('/api/usuarios/buscar-ou-criar', async (req, res) => {
  const { cpf, nome, email } = req.body;
  if (!cpf) return res.status(400).json({ erro: 'CPF é obrigatório.' });
  try {
    // Garante que o CPF seja armazenado apenas com números
    const cpfLimpo = cpf.replace(/[^0-9]/g, '');
    const busca = await pool.query('SELECT * FROM usuarios WHERE REPLACE(REPLACE(REPLACE(cpf, \'.\', \'\'), \'-\', \'\'), \'/\', \'\') = $1', [cpfLimpo]);
    if (busca.rows.length > 0) return res.json(busca.rows[0]);
    const novo = await pool.query(`INSERT INTO usuarios (cpf, nome, email, cargo, is_adm, senha) VALUES ($1, $2, $3, 'Agente', false, '123456') ON CONFLICT (cpf) DO UPDATE SET nome = EXCLUDED.nome, email = EXCLUDED.email RETURNING *;`, [cpfLimpo, nome || 'Usuário', email || '']);
    res.status(201).json(novo.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro interno.' }); }
});

app.get('/api/usuarios', async (req, res) => {
  try { const r = await pool.query('SELECT id, cpf, nome, email, cargo, is_adm, criado_em FROM usuarios ORDER BY nome'); res.json(r.rows); }
  catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.post('/api/usuarios/cadastrar-admin', async (req, res) => {
  const { cpf, nome, email, cargo, senha, admin_solicitante_cpf } = req.body;
  if (!cpf || !nome) return res.status(400).json({ erro: 'CPF e nome são obrigatórios.' });
  if (!admin_solicitante_cpf) return res.status(400).json({ erro: 'CPF do admin solicitante é obrigatório.' });
  try {
    const adminResult = await pool.query('SELECT is_adm FROM usuarios WHERE cpf = $1', [admin_solicitante_cpf.replace(/[^0-9]/g, '')]);
    if (adminResult.rows.length === 0) return res.status(403).json({ erro: 'Admin solicitante não encontrado.' });
    if (adminResult.rows[0].is_adm !== true) return res.status(403).json({ erro: 'Apenas administradores podem cadastrar novos admins.' });
    const cpfLimpo = cpf.replace(/[^0-9]/g, '');
    const existente = await pool.query('SELECT id FROM usuarios WHERE cpf = $1', [cpfLimpo]);
    if (existente.rows.length > 0) return res.status(409).json({ erro: 'CPF já cadastrado.' });
    const novo = await pool.query(`INSERT INTO usuarios (cpf, nome, email, cargo, is_adm, senha) VALUES ($1, $2, $3, $4, true, $5) RETURNING id, cpf, nome, email, cargo, is_adm, criado_em;`, [cpfLimpo, nome, email || '', cargo || 'Administrador', senha || '123456']);
    res.status(201).json({ mensagem: 'Administrador cadastrado!', usuario: novo.rows[0] });
  } catch (err) { res.status(500).json({ erro: 'Erro interno.' }); }
});

app.post('/api/login', async (req, res) => {
  const { login, pass } = req.body;
  if (!login || !pass) return res.status(400).json({ acesso: 'negado', mensagem: 'Usuário e senha são obrigatórios.' });
  try {
    const cpfLimpo = login.replace(/[^0-9]/g, '');
    const resultado = await pool.query('SELECT * FROM usuarios WHERE cpf = $1 OR LOWER(nome) = LOWER($2)', [cpfLimpo, login.trim()]);
    if (resultado.rows.length === 0) return res.status(401).json({ acesso: 'negado', mensagem: 'Usuário não encontrado.' });
    const usuario = resultado.rows[0];
    if (usuario.senha !== pass) return res.status(401).json({ acesso: 'negado', mensagem: 'Senha incorreta.' });
    res.json({ acesso: 'permitido', nome: usuario.nome, email: usuario.email || '', cpf: usuario.cpf, adm: usuario.is_adm === true, cargo: usuario.cargo || 'Agente' });
  } catch (err) { res.status(500).json({ acesso: 'negado', mensagem: 'Erro interno.' }); }
});

// ==========================================
// TABELAS BASE
// ==========================================
pool.query(`CREATE TABLE IF NOT EXISTS vehicle_logs (id SERIAL PRIMARY KEY, agent_name VARCHAR(255), action_type VARCHAR(100), agente_nome VARCHAR(255), tipo_movimento VARCHAR(100), placa VARCHAR(10), modelo VARCHAR(255), quilometragem INTEGER, observations TEXT, data_hora_saida TIMESTAMP DEFAULT NOW());`).catch(err => console.error(err));
pool.query(`CREATE TABLE IF NOT EXISTS abastecimentos (id SERIAL PRIMARY KEY, placa VARCHAR(10) NOT NULL, agente_nome VARCHAR(255), litros DECIMAL(10,2) NOT NULL, valor_total DECIMAL(10,2), tipo_combustivel VARCHAR(100), posto VARCHAR(255), km_atual INTEGER, criado_em TIMESTAMP DEFAULT NOW());`).catch(err => console.error(err));

// ==========================================
// NOVAS TABELAS: NOTIFICAÇÕES, SOLICITAÇÕES, CHECKLISTS
// ==========================================
pool.query(`
  CREATE TABLE IF NOT EXISTS notificacoes (
    id SERIAL PRIMARY KEY, cpf_usuario VARCHAR(14) NOT NULL, tipo VARCHAR(50) NOT NULL,
    titulo VARCHAR(255) NOT NULL, mensagem TEXT, placa VARCHAR(10),
    data_ocorrencia TIMESTAMP DEFAULT NOW(), lida BOOLEAN DEFAULT false, criado_em TIMESTAMP DEFAULT NOW()
  );
`).catch(err => console.error(err));

pool.query(`
  CREATE TABLE IF NOT EXISTS solicitacoes_manutencao (
    id SERIAL PRIMARY KEY, placa VARCHAR(10) NOT NULL, agente_nome VARCHAR(255) NOT NULL,
    cpf_agente VARCHAR(14), tipo_problema VARCHAR(100) NOT NULL, descricao TEXT NOT NULL,
    km_atual INTEGER, status VARCHAR(50) DEFAULT 'pendente', criado_em TIMESTAMP DEFAULT NOW(), atualizado_em TIMESTAMP DEFAULT NOW()
  );
`).catch(err => console.error(err));

pool.query(`
  CREATE TABLE IF NOT EXISTS checklists (
    id SERIAL PRIMARY KEY, placa VARCHAR(10) NOT NULL, agente_nome VARCHAR(255) NOT NULL, cpf_agente VARCHAR(14),
    item_1_pneus BOOLEAN DEFAULT false, item_2_luzes BOOLEAN DEFAULT false, item_3_freios BOOLEAN DEFAULT false,
    item_4_oleo BOOLEAN DEFAULT false, item_5_agua BOOLEAN DEFAULT false, item_6_cintos BOOLEAN DEFAULT false,
    item_7_extintor BOOLEAN DEFAULT false, item_8_retrovisores BOOLEAN DEFAULT false,
    item_9_documentos BOOLEAN DEFAULT false, item_10_limpeza BOOLEAN DEFAULT false,
    observacoes TEXT, km_atual INTEGER, criado_em TIMESTAMP DEFAULT NOW()
  );
`).catch(err => console.error(err));

// ==========================================
// NOVOS ENDPOINTS: NOTIFICAÇÕES
// ==========================================
app.get('/api/notificacoes/:cpf', async (req, res) => {
  try {
    const r = await pool.query(`SELECT * FROM notificacoes WHERE cpf_usuario = $1 ORDER BY data_ocorrencia DESC, id DESC`, [req.params.cpf]);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.put('/api/notificacoes/:id/lida', async (req, res) => {
  try { await pool.query(`UPDATE notificacoes SET lida = true WHERE id = $1`, [req.params.id]); res.json({ mensagem: 'OK' }); }
  catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// Endpoint para ADM: busca TODAS as notificações com filtros opcionais
app.get('/api/admin/notificacoes', async (req, res) => {
  const { tipo, nome, data_inicio, data_fim } = req.query;
  try {
    let query = `
      SELECT n.*, u.nome as nome_usuario 
      FROM notificacoes n 
      LEFT JOIN usuarios u ON REPLACE(REPLACE(REPLACE(u.cpf, '.', ''), '-', ''), '/', '') = REPLACE(REPLACE(REPLACE(n.cpf_usuario, '.', ''), '-', ''), '/', '')
    `;
    const conditions = [];
    const values = [];

    if (tipo && tipo.trim() !== '') {
      values.push(tipo.trim());
      conditions.push(`n.tipo = $${values.length}`);
    }
    if (nome && nome.trim() !== '') {
      values.push(`%${nome.trim().toLowerCase()}%`);
      conditions.push(`LOWER(u.nome) LIKE $${values.length}`);
    }
    if (data_inicio && data_inicio.trim() !== '') {
      values.push(data_inicio.trim());
      conditions.push(`n.data_ocorrencia >= $${values.length}::timestamp`);
    }
    if (data_fim && data_fim.trim() !== '') {
      values.push(data_fim.trim());
      conditions.push(`n.data_ocorrencia <= $${values.length}::timestamp + interval '1 day'`);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }
    query += ' ORDER BY n.data_ocorrencia DESC, n.id DESC';

    const r = await pool.query(query, values);
    res.json(r.rows);
  } catch (err) {
    console.error('Erro ao buscar notificações admin:', err);
    res.status(500).json({ erro: 'Erro.' });
  }
});

// ==========================================
// NOVOS ENDPOINTS: SOLICITAÇÕES DE MANUTENÇÃO
// ==========================================
app.post('/api/solicitacoes-manutencao', async (req, res) => {
  const { placa, agente_nome, cpf_agente, tipo_problema, descricao, km_atual } = req.body;
  if (!placa || !agente_nome || !tipo_problema || !descricao) return res.status(400).json({ erro: 'Campos obrigatórios.' });
  try {
    const r = await pool.query(`INSERT INTO solicitacoes_manutencao (placa, agente_nome, cpf_agente, tipo_problema, descricao, km_atual) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *;`, [placa.toUpperCase(), agente_nome, cpf_agente || '', tipo_problema, descricao, km_atual ? Number(km_atual) : null]);
    res.status(201).json(r.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.get('/api/solicitacoes-manutencao/:cpf', async (req, res) => {
  try {
    const r = await pool.query(`SELECT * FROM solicitacoes_manutencao WHERE cpf_agente = $1 ORDER BY criado_em DESC`, [req.params.cpf]);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// ==========================================
// NOVOS ENDPOINTS: CHECKLIST DE INSPEÇÃO
// ==========================================
app.post('/api/checklists', async (req, res) => {
  const { placa, agente_nome, cpf_agente, item_1_pneus, item_2_luzes, item_3_freios, item_4_oleo, item_5_agua, item_6_cintos, item_7_extintor, item_8_retrovisores, item_9_documentos, item_10_limpeza, observacoes, km_atual } = req.body;
  if (!placa || !agente_nome) return res.status(400).json({ erro: 'Placa e agente obrigatórios.' });
  try {
    const r = await pool.query(`INSERT INTO checklists (placa, agente_nome, cpf_agente, item_1_pneus, item_2_luzes, item_3_freios, item_4_oleo, item_5_agua, item_6_cintos, item_7_extintor, item_8_retrovisores, item_9_documentos, item_10_limpeza, observacoes, km_atual) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING *;`, [placa.toUpperCase(), agente_nome, cpf_agente || '', item_1_pneus || false, item_2_luzes || false, item_3_freios || false, item_4_oleo || false, item_5_agua || false, item_6_cintos || false, item_7_extintor || false, item_8_retrovisores || false, item_9_documentos || false, item_10_limpeza || false, observacoes || '', km_atual ? Number(km_atual) : null]);
    res.status(201).json(r.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.get('/api/checklists/:cpf', async (req, res) => {
  try {
    const r = await pool.query(`SELECT * FROM checklists WHERE cpf_agente = $1 ORDER BY criado_em DESC`, [req.params.cpf]);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

// ==========================================
// NOVOS ENDPOINTS: DETALHES DO USUÁRIO
// ==========================================
app.get('/api/usuarios/detalhes/:cpf', async (req, res) => {
  try {
    // Busca pelo CPF limpo (apenas números), tolerando formatação antiga no banco
    const cpfLimpo = req.params.cpf.replace(/[^0-9]/g, '');
    const r = await pool.query(
      `SELECT id, cpf, nome, email, cargo, is_adm, criado_em, atualizado_em FROM usuarios 
       WHERE REPLACE(REPLACE(REPLACE(cpf, '.', ''), '-', ''), '/', '') = $1`,
      [cpfLimpo]
    );
    if (r.rows.length === 0) return res.status(404).json({ erro: 'Usuário não encontrado.' });
    const user = r.rows[0];
    // Busca contagem real de movimentações e abastecimentos pelo nome do agente
    const totalMov = await pool.query(
      'SELECT COUNT(*) as total FROM vehicle_logs WHERE LOWER(agent_name) = LOWER($1)',
      [user.nome]
    );
    const totalAbast = await pool.query(
      'SELECT COUNT(*) as total FROM abastecimentos WHERE LOWER(agente_nome) = LOWER($1)',
      [user.nome]
    );
    // Retorna CPF limpo para manter consistência com o frontend
    res.json({
      ...user,
      cpf: cpfLimpo,
      total_movimentacoes: parseInt(totalMov.rows[0]?.total || '0'),
      total_abastecimentos: parseInt(totalAbast.rows[0]?.total || '0')
    });
  } catch (err) { console.error('Erro em /usuarios/detalhes:', err); res.status(500).json({ erro: 'Erro.' }); }
});

// ==========================================
// SEEDS
// ==========================================
const seedViaturas = async () => {
  const viaturas = [
    { placa: 'PCP1001', modelo: 'Fiat Toro', cor: 'Branco', status: 'disponivel', km_inicial: 45000 },
    { placa: 'PCP1002', modelo: 'Renault Duster', cor: 'Prata', status: 'disponivel', km_inicial: 38000 },
    { placa: 'PCP1003', modelo: 'Toyota Hilux', cor: 'Preto', status: 'indisponivel', km_inicial: 72000 },
    { placa: 'PCP1004', modelo: 'Fiat Argo', cor: 'Cinza', status: 'disponivel', km_inicial: 15000 },
    { placa: 'PCP1005', modelo: 'Chevrolet Trailblazer', cor: 'Vermelho', status: 'disponivel', km_inicial: 55000 },
    { placa: 'PCP1006', modelo: 'Volkswagen Polo', cor: 'Branco', status: 'disponivel', km_inicial: 8000 },
    { placa: 'PCP1007', modelo: 'Mitsubishi L200', cor: 'Prata', status: 'indisponivel', km_inicial: 63000 },
    { placa: 'PCP1008', modelo: 'Ford Ranger', cor: 'Azul', status: 'disponivel', km_inicial: 28000 },
    { placa: 'PCP1009', modelo: 'Chevrolet S10', cor: 'Preto', status: 'disponivel', km_inicial: 41000 },
    { placa: 'PCP1010', modelo: 'Renault Oroch', cor: 'Branco', status: 'disponivel', km_inicial: 2000 },
  ];
  for (const v of viaturas) {
    await pool.query(`INSERT INTO viaturas (placa, modelo, cor, status, quilometragem_inicial) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (placa) DO UPDATE SET modelo=EXCLUDED.modelo, cor=EXCLUDED.cor, status=EXCLUDED.status, quilometragem_inicial=EXCLUDED.quilometragem_inicial;`, [v.placa, v.modelo, v.cor, v.status, v.km_inicial]).catch(() => {});
  }
  console.log('Seed de viaturas concluído.');
};

const seedHistorico = async () => {
  const logs = [
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Saída de Viatura', placa: 'PCP1001', modelo: 'Fiat Toro (Branco)', km: 45600, obs: 'Saída - KM: 45600', data: '2026-07-15T08:15:00' },
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Devolução de Viatura', placa: 'PCP1001', modelo: 'Fiat Toro (Branco)', km: 45800, obs: 'Devolução - KM: 45800', data: '2026-07-15T17:30:00' },
    { agente: 'Carlos Alberto da Silva', tipo: 'Saída de Viatura', placa: 'PCP1003', modelo: 'Toyota Hilux (Preto)', km: 72300, obs: 'Saída - KM: 72300', data: '2026-07-16T07:45:00' },
    { agente: 'Carlos Alberto da Silva', tipo: 'Devolução de Viatura', placa: 'PCP1003', modelo: 'Toyota Hilux (Preto)', km: 72450, obs: 'Devolução - KM: 72450', data: '2026-07-16T18:10:00' },
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Saída de Viatura', placa: 'PCP1002', modelo: 'Renault Duster (Prata)', km: 38200, obs: 'Saída - KM: 38200', data: '2026-07-17T08:30:00' },
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Devolução de Viatura', placa: 'PCP1002', modelo: 'Renault Duster (Prata)', km: 38400, obs: 'Devolução - KM: 38400', data: '2026-07-17T16:45:00' },
    { agente: 'Ana Paula Oliveira', tipo: 'Saída de Viatura', placa: 'PCP1005', modelo: 'Chevrolet Trailblazer (Vermelho)', km: 55200, obs: 'Saída - KM: 55200', data: '2026-07-18T09:00:00' },
    { agente: 'Ana Paula Oliveira', tipo: 'Devolução de Viatura', placa: 'PCP1005', modelo: 'Chevrolet Trailblazer (Vermelho)', km: 55450, obs: 'Devolução - KM: 55450', data: '2026-07-18T19:30:00' },
    { agente: 'Marcos Vinicius Lima', tipo: 'Saída de Viatura', placa: 'PCP1007', modelo: 'Mitsubishi L200 (Prata)', km: 63200, obs: 'Saída - KM: 63200', data: '2026-07-19T06:50:00' },
    { agente: 'Marcos Vinicius Lima', tipo: 'Devolução de Viatura', placa: 'PCP1007', modelo: 'Mitsubishi L200 (Prata)', km: 63450, obs: 'Devolução - KM: 63450', data: '2026-07-19T17:20:00' },
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Abastecimento', placa: 'PCP1002', modelo: 'Renault Duster', km: 38200, obs: 'Abastecimento: 45L Diesel S10 - Posto BR - Recife', data: '2026-07-17T08:45:00' },
    { agente: 'Fabio Fernandes dos Santos', tipo: 'Abastecimento', placa: 'PCP1001', modelo: 'Fiat Toro', km: 45600, obs: 'Abastecimento: 40L Gasolina Comum - Ipiranga', data: '2026-07-15T08:30:00' },
    { agente: 'Carlos Alberto da Silva', tipo: 'Abastecimento', placa: 'PCP1003', modelo: 'Toyota Hilux', km: 72300, obs: 'Abastecimento: 55L Diesel S10 - Shell', data: '2026-07-16T08:00:00' },
  ];
  for (const log of logs) {
    await pool.query(`INSERT INTO vehicle_logs (agent_name, action_type, agente_nome, tipo_movimento, placa, modelo, quilometragem, observations, data_hora_saida) VALUES ($1,$2,$1,$2,$3,$4,$5,$6,$7)`, [log.agente, log.tipo, log.placa, log.modelo, log.km, log.obs, log.data]).catch(() => {});
  }
  console.log('Seed de histórico concluído.');
};

const seedAbastecimentos = async () => {
  const abs = [
    { placa: 'PCP1001', agente: 'Fabio Fernandes dos Santos', litros: 40.00, valor: 256.80, combustivel: 'Gasolina Comum', posto: 'Posto Ipiranga - Olinda', km: 45600 },
    { placa: 'PCP1002', agente: 'Fabio Fernandes dos Santos', litros: 45.00, valor: 280.35, combustivel: 'Diesel S10', posto: 'Posto BR - Recife', km: 38200 },
    { placa: 'PCP1003', agente: 'Carlos Alberto da Silva', litros: 55.00, valor: 342.65, combustivel: 'Diesel S10', posto: 'Posto Shell - Jaboatão', km: 72300 },
    { placa: 'PCP1005', agente: 'Ana Paula Oliveira', litros: 35.00, valor: 224.70, combustivel: 'Gasolina Aditivada', posto: 'Posto Petrobras - Recife', km: 55200 },
    { placa: 'PCP1007', agente: 'Marcos Vinicius Lima', litros: 50.00, valor: 311.50, combustivel: 'Diesel S10', posto: 'Posto Ale - Paulista', km: 63200 },
    { placa: 'PCP1002', agente: 'Fabio Fernandes dos Santos', litros: 42.00, valor: 261.66, combustivel: 'Diesel S10', posto: 'Posto BR - Recife', km: 38400 },
    { placa: 'PCP1004', agente: 'Fabio Fernandes dos Santos', litros: 30.00, valor: 192.60, combustivel: 'Gasolina Comum', posto: 'Posto Ipiranga - Olinda', km: 15600 },
    { placa: 'PCP1008', agente: 'Ana Paula Oliveira', litros: 48.00, valor: 298.56, combustivel: 'Diesel Comum', posto: 'Posto Shell - Recife', km: 28300 },
  ];
  for (const a of abs) {
    await pool.query(`INSERT INTO abastecimentos (placa, agente_nome, litros, valor_total, tipo_combustivel, posto, km_atual) VALUES ($1,$2,$3,$4,$5,$6,$7)`, [a.placa, a.agente, a.litros, a.valor, a.combustivel, a.posto, a.km]).catch(() => {});
  }
  console.log('Seed de abastecimentos concluído.');
};

const seedManutencoes = async () => {
  const mps = [
    { placa: 'PCP1001', componente: 'Filtro de Ar', km_limite: 60000, km_atual: 45800 },
    { placa: 'PCP1001', componente: 'Pastilhas de Freio', km_limite: 70000, km_atual: 45800 },
    { placa: 'PCP1003', componente: 'Troca de Óleo e Filtro', km_limite: 82000, km_atual: 72450 },
    { placa: 'PCP1003', componente: 'Filtro de Combustível', km_limite: 92000, km_atual: 72450 },
    { placa: 'PCP1005', componente: 'Filtro de Ar', km_limite: 70000, km_atual: 55450 },
    { placa: 'PCP1007', componente: 'Troca de Óleo e Filtro', km_limite: 73000, km_atual: 63450 },
    { placa: 'PCP1007', componente: 'Pastilhas de Freio', km_limite: 88000, km_atual: 63450 },
    { placa: 'PCP1007', componente: 'Correia Dentada', km_limite: 118000, km_atual: 63450 },
    { placa: 'PCP1002', componente: 'Filtro de Combustível', km_limite: 58000, km_atual: 38400 },
  ];
  for (const m of mps) {
    await pool.query(`INSERT INTO manutencoes (placa, componente, km_limite, km_atual, status) VALUES ($1,$2,$3,$4,'pendente') ON CONFLICT DO NOTHING;`, [m.placa, m.componente, m.km_limite, m.km_atual]).catch(() => {});
  }
  console.log('Seed de manutenções concluído.');
};

const seedNotificacoes = async () => {
  const nots = [
    // Notificações para Fabio Fernandes (CPF 06611289461) - Agente
    { cpf: '06611289461', tipo: 'aviso', titulo: 'Manutenção Pendente', mensagem: 'Viatura PCP1001: Filtro de Ar precisa ser trocado.', placa: 'PCP1001', data: '2026-07-20T10:00:00' },
    { cpf: '06611289461', tipo: 'aviso', titulo: 'Vistoria Programada', mensagem: 'Viatura PCP1002 deve passar por vistoria até 30/08/2026.', placa: 'PCP1002', data: '2026-07-22T14:30:00' },
    { cpf: '06611289461', tipo: 'ocorrencia', titulo: 'Avaria Reportada', mensagem: 'Para-brisa trincado na viatura PCP1001.', placa: 'PCP1001', data: '2026-07-23T09:15:00' },
    { cpf: '06611289461', tipo: 'multa', titulo: 'Infração de Trânsito - Auto A67890', mensagem: 'Multa por excesso de velocidade na Av. Recife, 15/07/2026. Viatura PCP1002.', placa: 'PCP1002', data: '2026-07-25T11:30:00' },
    { cpf: '06611289461', tipo: 'multa', titulo: 'Infração de Trânsito - Auto B12345', mensagem: 'Multa por avanço de sinal vermelho em Olinda, 22/07/2026. Viatura PCP1004.', placa: 'PCP1004', data: '2026-07-26T08:15:00' },
    // Notificações para Delegado Titular (CPF 00000000191) - ADM
    { cpf: '00000000191', tipo: 'multa', titulo: 'Infração de Trânsito - Auto 12345', mensagem: 'Auto 12345 - placa PCP1001 em 15/07/2026, Recife. Motorista: Fabio Fernandes.', placa: 'PCP1001', data: '2026-07-18T16:45:00' },
    { cpf: '00000000191', tipo: 'aviso', titulo: 'Viatura com Manutenção Vencida', mensagem: 'Viatura PCP1003 (Toyota Hilux) está com manutenção vencida. Verificar painel.', placa: 'PCP1003', data: '2026-07-24T09:00:00' },
    // Notificações para Carlos Alberto (CPF 12345678901) - Agente
    { cpf: '12345678901', tipo: 'multa', titulo: 'Infração de Trânsito - Auto C99999', mensagem: 'Multa por estacionamento irregular em Jaboatão, 20/07/2026. Viatura PCP1005.', placa: 'PCP1005', data: '2026-07-21T14:00:00' },
    { cpf: '12345678901', tipo: 'aviso', titulo: 'Checklist Pendente', mensagem: 'Viatura PCP1005 não teve checklist preenchido hoje. Regularizar até 18h.', placa: 'PCP1005', data: '2026-07-25T07:45:00' },
    // Notificações para Ana Paula (CPF 23456789012) - Agente
    { cpf: '23456789012', tipo: 'ocorrencia', titulo: 'Arranhão na Lataria', mensagem: 'Viatura PCP1008 sofreu arranhão na porta dianteira. Registrar avaria.', placa: 'PCP1008', data: '2026-07-24T16:20:00' },
  ];
  for (const n of nots) {
    await pool.query(`INSERT INTO notificacoes (cpf_usuario, tipo, titulo, mensagem, placa, data_ocorrencia) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING;`, [n.cpf, n.tipo, n.titulo, n.mensagem, n.placa, n.data]).catch(() => {});
  }
  console.log('Seed de notificações concluído.');
};

setTimeout(async () => {
  try {
    // Primeiro corrige KM de viaturas existentes, depois aplica seeds
    await corrigirKmInicial();
    await seedViaturas();
    await seedHistorico();
    await seedAbastecimentos();
    await seedManutencoes();
    await seedNotificacoes();
    console.log('Todos os seeds concluídos.');
  } catch (err) { console.error('Erro nos seeds:', err); }
}, 2000);

// ==========================================
// ABASTECIMENTOS
// ==========================================
app.get('/api/abastecimentos', async (req, res) => {
  const { placa, agente } = req.query;
  try {
    let query = 'SELECT * FROM abastecimentos';
    const conditions = [], values = [];
    if (placa) { conditions.push(`placa = $${values.length + 1}`); values.push(placa.toUpperCase()); }
    if (agente) { conditions.push(`LOWER(agente_nome) = LOWER($${values.length + 1})`); values.push(agente); }
    if (conditions.length > 0) query += ' WHERE ' + conditions.join(' AND ');
    query += ' ORDER BY criado_em DESC';
    const r = await pool.query(query, values);
    res.json(r.rows);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.post('/api/abastecimentos', async (req, res) => {
  const { placa, agente_nome, litros, valor_total, tipo_combustivel, posto, km_atual } = req.body;
  if (!placa || !litros) return res.status(400).json({ erro: 'Placa e litros obrigatórios.' });
  try {
    const r = await pool.query(`INSERT INTO abastecimentos (placa, agente_nome, litros, valor_total, tipo_combustivel, posto, km_atual) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *;`, [placa.toUpperCase(), agente_nome || '', Number(litros), valor_total ? Number(valor_total) : null, tipo_combustivel || 'Gasolina Comum', posto || '', km_atual ? Number(km_atual) : null]);
    res.status(201).json(r.rows[0]);
  } catch (err) { res.status(500).json({ erro: 'Erro.' }); }
});

app.listen(PORT, () => { console.log(`Servidor rodando na porta ${PORT}`); });