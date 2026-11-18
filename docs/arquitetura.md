# Arquitetura

Detalhamento nó a nó dos três workflows. Para a visão geral, ver o README.

## 1. `atendimento-sdr.json`

O arquivo reúne dois fluxos independentes: o atendimento (gatilho por webhook) e a ingestão da base de conhecimento (gatilho agendado).

### 1.1 Entrada e roteamento

```
Webhook WhatsApp (POST /agente-sdr-whatsapp)
  -> Dados                      normaliza o payload do provedor: telefone, nome no WhatsApp,
                                tipo de conteúdo, texto, id da sessão, evento, número de destino
  -> Rotas
       Numero admin             mensagem do próprio número administrativo: ignorada
       Rota normal              mensagem para o número da empresa: segue
       Treinamento IA           texto começa com PREFIXO_TREINAMENTO: Agente Treinamento RAG
```

Na rota normal, `Supabase` busca o lead em `dados_cliente`; se não existir, `Supabase1` cria a linha. Em seguida `Switch4` separa por evento:

| Evento | Saída | Tratamento |
|--------|-------|------------|
| `SESSION_UPDATE` | `outcoming` | Atividade do atendente humano. `Rotas1`: texto "Atendimento finalizado" espera 1 min e reativa a IA; qualquer outro texto pausa a IA (`atendimento_ia = 'pause'`) e grava a mensagem na memória do agente |
| `MESSAGE_RECEIVED` | `incoming` | Mensagem do lead. `Clear Nurturing` zera o passo de nutrição (o lead respondeu), `Verificar Pause` decide entre IA ativa e IA pausada |

Com a IA pausada, a mensagem do lead só é gravada em `n8n_chat_histories`, para que o agente tenha o contexto completo se for reativado.

### 1.2 Normalização por tipo de mídia

`Switch1` separa por `content_type`:

| Tipo | Tratamento |
|------|-----------|
| `TEXT` | Vai direto para o buffer |
| `AUDIO`, `VIDEO` | Base64 -> arquivo -> transcrição (OpenAI) -> buffer |
| `IMAGE` | Base64 -> arquivo -> descrição curta por modelo de visão (`gpt-4o-mini`); se houver legenda, legenda + descrição -> buffer |

### 1.3 Agrupamento de mensagens (debounce)

Lead de WhatsApp manda a ideia em várias mensagens curtas. Responder a cada uma gera conversa atropelada e custo dobrado.

```
push no Redis (lista com chave = telefone)
  -> Get Memory 1               lê a lista
  -> Wait3 (10 s)
  -> Get Memory 2               lê de novo
  -> Compara Get Memory1        listas iguais? então nenhuma mensagem nova chegou
       sim -> Mensagem Completa (concatena e remove duplicatas)
       não -> a execução termina; a execução da mensagem mais nova assume
```

Depois da resposta, `Delete Memory` limpa a lista.

### 1.4 Busca e resposta

```
Mensagem Completa
  -> Agente Rag                 ferramenta buscar_documentos (Supabase Vector Store, top 2,
                                embeddings text-embedding-3-small); devolve trecho ou vazio
  -> Atendente                  prompt de sistema prompts/atendente-sdr.md
                                entrada = mensagem consolidada + trecho da base
                                memória: Postgres Chat Memory, 30 mensagens, sessão = telefone
  -> Switch2                    a resposta contém a frase de encaminhamento?
  -> Busca Telefone (em paralelo) upsert em chats, grava a troca em chat_messages, limpa o Redis
```

### 1.5 Resposta normal

```
Switch2 "Continuar na IA"
  -> Parser  Chain              prompts/divisao-mensagens.md, saída {"messages": [...]}
  -> Split de Mensagem
  -> Loop Over Items3           envia cada bloco (Send text to contact) com 1 s de intervalo
  -> (fim do loop) Get Nurturing Status -> If Not Enrolled -> Start Nurturing
                                inscreve o lead na nutrição: nurturing_step = 1, nurturing_enrolled_at = agora
```

A inscrição acontece a cada resposta do agente, mas só se o lead não estiver na sequência. Quando o lead responde, `Clear Nurturing` zera o passo; a próxima resposta do agente reinscreve com o relógio zerado.

### 1.6 Encaminhamento

```
Switch2 "Encaminhar para CRM"
  -> Send text in session       envia a mensagem final dentro da sessão
  -> Wait - 2
  -> ListMessages-Supabase2 -> Aggregate2 -> Code6
                                monta a conversa inteira em texto
  -> Basic LLM Chain1           prompts/extracao-lead.md + Structured Output Parser
  -> Dados lead -> Atualiza Dados Cliente
  -> Enviar Lead ao CRM         POST JSON em CRM_LEADS_URL (credencial Header Auth)
  -> Transfer session           transfere a sessão para o departamento humano
       -> Pausar IA1            atendimento_ia = 'pause'
       -> Notificação Time      resumo do lead para o número do time
```

### 1.7 Ingestão da base de conhecimento

```
Schedule Trigger (5h)
  -> Deleta linhas antigas do documento1   apaga todo o conteúdo de documents
  -> Google Drive                          lista a pasta GOOGLE_DRIVE_PASTA_BASE_ID
  -> Download File1                        Google Docs convertidos para texto
  -> Extract Document Text
  -> Insert into Supabase Vectorstore1     Character Text Splitter (separador "\n\n",
                                           800 caracteres, sobreposição 100) + embeddings
```

Recriar a base inteira a cada execução é simples e evita trechos órfãos de documentos editados ou removidos. Serve para bases pequenas; para bases grandes, trocar por ingestão incremental por arquivo.

Os nós `Extract PDF Text`, `Extract from Excel`, `Extract from Excel2`, `Aggregate1` e `Summarize1` ficam disponíveis para PDFs e planilhas, mas não estão ligados ao fluxo: ligue-os com um `Switch` por `mimeType` se a pasta tiver esses formatos.

## 2. `nutricao-agendada.json`

```
Trigger 30min
  -> Get Leads Nurturing        dados_cliente com nurturing_step <> 0
  -> Loop Leads
       -> Check Timing          horas desde a inscrição; decide enviar, esperar ou expirar
       -> IF Window Expired     IA pausada, sem data, ou >= 23 h: Reset Expired (step = 0)
       -> IF Should Send        passo 1 >= 3 h, passo 2 >= 10 h, passo 3 >= 21 h
       -> Get History -> Aggregate History -> Format History   últimas 8 trocas
       -> Generate Followup     prompts/nutricao-followup.md
       -> Send Nurturing WTS -> Wait 2s
       -> Compute Next Step     1 -> 2 -> 3 -> 0
       -> Update Step
```

O limite de 23 h existe porque o WhatsApp só permite mensagem livre até 24 h depois da última mensagem do contato; depois disso, só template aprovado.

## 3. `reenvio-manual-crm.json`

Recuperação para leads que não chegaram ao CRM (credencial expirada, CRM fora do ar). Gatilho manual.

```
Manual Trigger
  -> Busca Leads Supabase       dados_cliente com atendimento_ia <> 'pause'
  -> Loop Leads
       -> Set Telefone -> Pausar IA2
       -> ListMessages-Supabase -> Aggregate -> Code
       -> Basic LLM Chain       mesma extração do fluxo principal
       -> Dados lead1 -> Atualiza Dados Cliente1
       -> Enviar Lead ao CRM
```

O filtro padrão pega todo lead ainda não encaminhado e pausa a IA de cada um. Antes de rodar, ajuste o filtro de `Busca Leads Supabase` para o recorte desejado (por exemplo, por data de criação).

## Modelo de dados

Ver `supabase/schema.sql`.

| Tabela | Escrita por | Lida por |
|--------|-------------|----------|
| `chats` | Atendimento | Atendimento |
| `chat_messages` | Atendimento | Encaminhamento, nutrição, reenvio, revisão diária |
| `dados_cliente` | Atendimento, encaminhamento, nutrição, reenvio | Todos |
| `n8n_chat_histories` | Memória do agente, mensagens com IA pausada | Agente atendente |
| `documents` | Ingestão | Agente RAG |
