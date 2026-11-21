# Instalação e configuração

1. **Banco.** Crie um projeto no Supabase e rode [`supabase/schema.sql`](../supabase/schema.sql).
2. **n8n.** Instale o nó da comunidade `n8n-nodes-wts` e defina `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (os workflows leem configuração via `$env`).
3. **Variáveis.** Copie [`.env.example`](../.env.example) para as variáveis de ambiente da instância n8n e preencha.
4. **Credenciais no n8n.** Os workflows referenciam credenciais por nome; crie-as e selecione-as em cada nó após importar:

   | Credencial | Tipo |
   |-----------|------|
   | OpenAI | OpenAI API |
   | Supabase | Supabase API (URL + chave de serviço) |
   | Postgres (Supabase) | Postgres, apontando para o banco do Supabase |
   | Redis | Redis |
   | WTS Chat (WhatsApp) | WTS API |
   | Google Drive | Google Drive OAuth2 |
   | Google Sheets | Google Sheets OAuth2 |
   | CRM (Header Auth) | Header Auth com o cabeçalho de autenticação do seu CRM |

5. **Importar** os três arquivos de [`workflows/`](../workflows/) (menu Import from File).
6. **CRM.** O nó `Enviar Lead ao CRM` faz `POST` em `CRM_LEADS_URL` com um JSON genérico (`nome`, `telefone`, `email`, `interesse`, `tipo_imovel`, `regiao`, `faixa_valor`, `observacoes`, `origem`, `tags`). Ajuste o corpo ao formato do seu CRM. A versão original usava o endpoint de integração de leads de um CRM comercial, com atualização por telefone.
7. **Webhook.** Aponte o webhook do provedor de WhatsApp para `https://<seu-n8n>/webhook/agente-sdr-whatsapp`.
8. **Base.** Coloque os documentos na pasta do Drive e rode a ingestão manualmente uma vez.
9. **Revisão diária.** No GitHub, crie os secrets `ANTHROPIC_API_KEY`, `N8N_API_URL`, `N8N_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` e `CRM_LEADS_URL`.

