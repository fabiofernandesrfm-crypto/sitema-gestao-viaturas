/**
 * Script de teste de conexão com o PostgreSQL
 * Uso: node test_db_connection.js
 */
const { Pool } = require('pg');
require('dotenv').config();

console.log('=== Teste de Conexão PostgreSQL ===');
console.log('Variáveis de ambiente:');
console.log('  DB_HOST:', process.env.DB_HOST);
console.log('  DB_PORT:', process.env.DB_PORT);
console.log('  DB_USER:', process.env.DB_USER);
console.log('  DB_PASSWORD:', process.env.DB_PASSWORD ? '***' : '(não definida)');
console.log('  DB_NAME:', process.env.DB_NAME);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || `postgres://${process.env.DB_USER}:${process.env.DB_PASSWORD}@${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}?sslmode=disable`,
});

pool.query('SELECT NOW() AS current_time, current_database() AS db_name')
  .then(res => {
    console.log('\n✅ Conexão bem-sucedida!');
    console.log('  Hora do servidor:', res.rows[0].current_time);
    console.log('  Banco de dados:', res.rows[0].db_name);
    return pool.end();
  })
  .then(() => {
    console.log('✅ Teste concluído com sucesso.\n');
    process.exit(0);
  })
  .catch(err => {
    console.error('\n❌ Erro na conexão:');
    console.error('  Código:', err.code);
    console.error('  Mensagem:', err.message);
    console.error('  Detalhes:', err.detail || '(sem detalhes)');
    return pool.end().then(() => process.exit(1));
  });