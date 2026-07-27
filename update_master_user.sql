-- =============================================
-- SGV: Atualizar usuário para Master/Administrador
-- Execute com:
--   psql -h 127.0.0.1 -p 5433 -U sgv_user -d sgv_viaturas -f update_master_user.sql
--   (senha: sgv_password_2024)
-- =============================================

UPDATE usuarios 
SET 
    cargo = 'Master/Administrador',
    is_adm = true,
    is_master = true,
    atualizado_em = NOW()
WHERE REPLACE(REPLACE(REPLACE(cpf, '.', ''), '-', ''), '/', '') = '06611289461';

-- Verifica o resultado
SELECT id, cpf, nome, email, cargo, is_adm, is_master, criado_em, atualizado_em 
FROM usuarios 
WHERE REPLACE(REPLACE(REPLACE(cpf, '.', ''), '-', ''), '/', '') = '06611289461';