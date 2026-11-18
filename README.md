# agente-sdr-whatsapp

Agente de pré-vendas (SDR) para WhatsApp construído em n8n: atende o lead na hora, qualifica, consulta uma base de conhecimento, entrega o lead pronto ao CRM e transfere a conversa para um humano. Inclui nutrição automática de quem para de responder e uma revisão diária da operação por modelo de linguagem via GitHub Actions.

Esta é a versão pública de um agente em produção para um cliente real. Cliente, marca, prompts, base de conhecimento e identificadores foram substituídos por uma empresa fictícia, a **Imobiliária Exemplo**, com a agente **Lia**.

## Problema

Lead que chega pelo WhatsApp esfria rápido. Fora do horário comercial, ou com o time ocupado, a primeira resposta demora horas, e quando o corretor chega a conversa já morreu ou o lead falou com o concorrente. Ao mesmo tempo, boa parte dos contatos não está pronta para falar com um vendedor, e passar todos adiante desperdiça o tempo do time.

## O que o agente faz

- Responde em segundos, a qualquer hora, em texto, áudio (transcrição) ou imagem (descrição).
- Agrupa mensagens picadas do lead antes de responder.
- Conduz a qualificação em dois níveis e só encaminha quem está qualificado **e** pediu para falar com um corretor.
- Responde dúvidas operacionais a partir de uma base de conhecimento vetorial, sem inventar.
- No encaminhamento: extrai os dados da conversa, atualiza o cadastro, envia ao CRM, transfere a sessão para o time e avisa o time com um resumo.
- Pausa sozinho quando um humano assume a conversa e volta quando o atendimento é finalizado.
- Retoma, em até três mensagens dentro da janela de 24 h, leads que pararam de responder.
- Gera um relatório diário de falhas de integração e qualidade das conversas.

## Arquitetura

```
                 +------------------+
 Lead (WhatsApp) | Provedor WhatsApp|  WTS Chat
                 +--------+---------+
                          | webhook
                          v
+---------------------------------------------------------------------+
| n8n — atendimento-sdr.json                                          |
|                                                                     |
|  Dados -> Rotas -> evento?                                          |
|              |        |- humano escreveu -> pausa / reativa IA      |
|              |        '- lead escreveu ---> IA pausada? -> só grava |
|              |                                  |                   |
|              |                    texto / áudio / imagem            |
|              |                    (transcrição, visão)              |
|              |                                  v                   |
|              |                     buffer Redis + espera 10 s       |
|              |                                  v                   |
|              |                     Agente RAG ---------> Supabase   |
|              |                                  v        pgvector   |
|              |                     Atendente <---------> Postgres   |
|              |                     (gpt-4.1-mini)        memória    |
|              |                          |                           |
|              |          +---------------+----------------+          |
|              |          v                                v          |
|              |   divide em blocos              extrai dados do lead |
|              |   envia com intervalo           atualiza cadastro    |
|              |   inscreve na nutrição          POST no CRM          |
|              |                                 transfere p/ humano  |
|              |                                 notifica o time      |
|              '- prefixo de treino -> agente grava Q&A no Sheets     |
|                                                                     |
|  05h diário: Google Drive -> chunks -> embeddings -> pgvector       |
+---------------------------------------------------------------------+

n8n — nutricao-agendada.json   a cada 30 min: passos 3 h / 10 h / 21 h
n8n — reenvio-manual-crm.json  recuperação manual de leads fora do CRM
GitHub Actions                 08h diário: revisão da operação -> relatório versionado
```

Detalhe nó a nó em [`docs/arquitetura.md`](docs/arquitetura.md).

| Camada | Tecnologia |
|--------|-----------|
| Orquestração | n8n (self-hosted) |
| Canal | WhatsApp via WTS Chat (nó da comunidade `n8n-nodes-wts`) |
| Modelos | OpenAI: `gpt-4.1-mini` (conversa), `gpt-4o-mini` (imagem), transcrição de áudio, `text-embedding-3-small` |
| Banco | Supabase (Postgres + pgvector) |
| Buffer | Redis |
| Base de conhecimento | Google Drive (fonte) e Google Sheets (treino pelo WhatsApp) |
| CRM | Qualquer CRM com endpoint HTTP para criação de lead |
| Revisão | GitHub Actions + `anthropics/claude-code-action` |

## Fluxo da conversa e qualificação

1. **Saudação** curta, com pedido do nome.
2. **Dados básicos**, um por vez, intercalados na conversa: nome, interesse (comprar, alugar ou anunciar) e região.
3. **Necessidade**: tipo de imóvel, faixa de valor, prazo.
4. **Qualificação** e indicação do serviço adequado.
5. **Objeções** com respostas de referência no prompt.
6. **Encaminhamento**: o agente pergunta se o lead quer falar com um corretor; só com "sim" envia a mensagem fixa de encerramento.

| Nível | Critério | Ação |
|-------|----------|------|
| 1 (frio) | Falta nome, interesse ou região | Continua a conversa; nunca encaminha |
| 2 (qualificado) | Dados básicos + necessidade entendida | Pode encaminhar, após confirmação do lead |

A decisão de encaminhar é do modelo, mas o disparo é determinístico: o `Switch2` procura a frase fixa de encerramento na resposta. Isso mantém o fluxo de CRM fora do alcance de variações de redação e torna o gatilho testável.

Os critérios e campos são de exemplo e ficam em [`prompts/atendente-sdr.md`](prompts/atendente-sdr.md) e [`prompts/extracao-lead.md`](prompts/extracao-lead.md).

## RAG e memória

**Base de conhecimento.** Documentos de uma pasta do Google Drive são recriados no pgvector toda madrugada (chunks de 800 caracteres, sobreposição de 100). Um agente separado faz a busca (top 2) e devolve o trecho literal ou vazio; o atendente recebe esse trecho junto com a mensagem. A equipe pode acrescentar perguntas e respostas mandando uma mensagem com o prefixo de treino: um agente corrige o texto e grava na planilha que a ingestão lê. Exemplo de base em [`base-conhecimento/`](base-conhecimento/).

**Memória.** Três camadas com funções diferentes:

| Camada | Onde | Para quê |
|--------|------|----------|
| Buffer curto | Redis, chave = telefone | Juntar mensagens picadas; apagado após cada resposta |
| Memória do agente | Postgres (`n8n_chat_histories`), 30 mensagens | Contexto da conversa para o modelo, inclusive o que o humano disse com a IA pausada |
| Histórico legível | Supabase (`chat_messages`) | Extração de dados, nutrição, reenvio e revisão |

## Nutrição

Ao responder, o agente inscreve o lead numa sequência de três retomadas, geradas pelo modelo a partir das últimas oito trocas:

| Passo | Após | Objetivo |
|-------|------|----------|
| 1 | 3 h | Reabrir sem pressão |
| 2 | 10 h | Entregar um conteúdo ligado ao que o lead disse |
| 3 | 21 h | Despedida, porta aberta |

Qualquer resposta do lead zera a sequência. Com IA pausada ou após 23 h, o lead sai da sequência; depois de 24 h o WhatsApp só aceita template aprovado.

## Revisão diária automatizada

[`.github/workflows/revisao-diaria.yml`](.github/workflows/revisao-diaria.yml) roda às 8h e executa as instruções de [`revisao/agente-revisor.md`](revisao/agente-revisor.md):

- execuções com erro no n8n nas últimas 24 h;
- leads encaminhados sem correspondente no CRM ou com campos obrigatórios vazios;
- amostra de conversas: lead Nível 1 encaminhado, pergunta repetida, informação inventada, dúvida sem resposta na base.

O relatório é commitado em `revisao/relatorios/AAAA-MM-DD.md`. A revisão é somente leitura e não copia dados pessoais para o relatório. [`revisao/checklist.md`](revisao/checklist.md) cobre a revisão semanal e o diagnóstico manual.

## Decisões de design e limites

- **Transbordo para humano.** O agente não fecha negócio nem informa preço. No encaminhamento a sessão é transferida no provedor e a IA fica pausada até o atendente escrever "Atendimento finalizado". Toda mensagem do humano pausa a IA, então assumir a conversa não exige nenhuma ação extra.
- **Gatilho por frase fixa.** Simples e auditável, mas acoplado ao prompt: mudar a mensagem de encerramento exige mudar o `Switch2`.
- **Debounce por comparação.** Duas leituras do Redis com 10 s de intervalo; se a lista mudou, a execução desiste e a mais recente responde. Acrescenta até 10 s de latência em troca de uma resposta por ideia.
- **Mensagens em blocos.** Respostas longas são divididas em blocos de 300 a 500 caracteres com formatação nativa do WhatsApp e enviadas com 1 s de intervalo.
- **Busca separada da conversa.** O agente RAG só devolve trecho literal ou vazio; reduz invenção e mantém o prompt do atendente estável.
- **Reconstrução total da base.** Adequada a bases pequenas. Para volume maior, trocar por ingestão incremental.
- **JSON do CRM montado com `JSON.stringify`.** Aspas e quebras de linha no resumo da conversa não quebram o corpo da requisição.
- **Mídia.** Os nós de áudio e imagem leem base64 do payload do webhook. O formato desse campo depende do provedor de WhatsApp e precisa ser conferido na integração.
- **Rota de treino.** O `Switch` de entrada usa a primeira regra que casar; a regra do prefixo de treino vem depois da rota normal. Ajuste a ordem e restrinja o remetente ao número administrativo antes de usar em produção.
- **Sem testes automatizados** dos workflows; a validação é feita pela revisão diária e por execução manual no n8n.

## Como importar e configurar

1. **Banco.** Crie um projeto no Supabase e rode [`supabase/schema.sql`](supabase/schema.sql).
2. **n8n.** Instale o nó da comunidade `n8n-nodes-wts` e defina `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (os workflows leem configuração via `$env`).
3. **Variáveis.** Copie [`.env.example`](.env.example) para as variáveis de ambiente da instância n8n e preencha.
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

5. **Importar** os três arquivos de [`workflows/`](workflows/) (menu Import from File).
6. **CRM.** O nó `Enviar Lead ao CRM` faz `POST` em `CRM_LEADS_URL` com um JSON genérico (`nome`, `telefone`, `email`, `interesse`, `tipo_imovel`, `regiao`, `faixa_valor`, `observacoes`, `origem`, `tags`). Ajuste o corpo ao formato do seu CRM. A versão original usava o endpoint de integração de leads de um CRM comercial, com atualização por telefone.
7. **Webhook.** Aponte o webhook do provedor de WhatsApp para `https://<seu-n8n>/webhook/agente-sdr-whatsapp`.
8. **Base.** Coloque os documentos na pasta do Drive e rode a ingestão manualmente uma vez.
9. **Revisão diária.** No GitHub, crie os secrets `ANTHROPIC_API_KEY`, `N8N_API_URL`, `N8N_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` e `CRM_LEADS_URL`.

## Estrutura

```
.
├── .github/workflows/revisao-diaria.yml   revisão diária
├── base-conhecimento/                     base fictícia de exemplo
├── docs/arquitetura.md                    detalhamento nó a nó
├── prompts/                               prompts versionados, um por nó de modelo
├── revisao/
│   ├── agente-revisor.md                  instruções da revisão
│   ├── checklist.md                       revisão manual e diagnóstico
│   └── relatorios/                        relatórios gerados
├── supabase/schema.sql                    tabelas, pgvector e match_documents
├── workflows/
│   ├── atendimento-sdr.json               atendimento, encaminhamento e ingestão da base
│   ├── nutricao-agendada.json             follow-up de leads sem resposta
│   └── reenvio-manual-crm.json            recuperação de leads fora do CRM
├── .env.example
└── LICENSE
```

## Licença

MIT. Ver [`LICENSE`](LICENSE).
