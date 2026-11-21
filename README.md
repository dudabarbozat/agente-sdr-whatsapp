# Agente SDR para WhatsApp

Agente de pré-vendas construído em n8n: atende o lead na hora, qualifica, consulta uma base de conhecimento, entrega o lead pronto ao CRM e transfere a conversa para um humano.

Versão pública de um agente em produção para um cliente real. Cliente, marca, prompts, base de conhecimento e identificadores foram substituídos por uma empresa fictícia, a **Imobiliária Exemplo**, com a agente **Lia**.

## Para quem

Times comerciais que recebem leads pelo WhatsApp e perdem oportunidades pela demora na primeira resposta, ou gastam tempo com contatos que ainda não estão prontos para falar com um vendedor.

## O que o agente faz

- Responde em segundos, a qualquer hora, em texto, áudio (transcrição) ou imagem (descrição), agrupando mensagens picadas antes de responder.
- Qualifica em dois níveis e só encaminha quem está qualificado **e** pediu para falar com um corretor.
- Responde dúvidas a partir de uma base de conhecimento vetorial, sem inventar.
- No encaminhamento, extrai os dados da conversa, envia ao CRM, transfere a sessão e avisa o time com um resumo.
- Pausa quando um humano assume e volta quando o atendimento é finalizado.
- Retoma em até três mensagens, dentro da janela de 24 h, leads que pararam de responder.
- Revisão diária da operação por modelo de linguagem via GitHub Actions.

## Arquitetura

```
Lead (WhatsApp) -> WTS Chat -> webhook n8n (atendimento-sdr.json)
  -> evento: humano escreveu -> pausa / reativa IA
  -> lead escreveu -> texto / áudio / imagem -> buffer Redis (10 s)
  -> Agente RAG (Supabase pgvector) -> Atendente gpt-4.1-mini (memória Postgres)
  -> resposta em blocos + nutrição
  -> ou encaminhamento: extrai dados -> CRM -> transfere -> notifica o time

nutricao-agendada.json   a cada 30 min: retomadas em 3 h / 10 h / 21 h
reenvio-manual-crm.json  recuperação manual de leads fora do CRM
GitHub Actions           08h diário: revisão da operação -> relatório versionado
```

Detalhe nó a nó e decisões de design em [`docs/arquitetura.md`](docs/arquitetura.md).

| Camada | Tecnologia |
|--------|-----------|
| Orquestração | n8n (self-hosted) |
| Canal | WhatsApp via WTS Chat |
| Modelos | OpenAI (`gpt-4.1-mini`, `gpt-4o-mini`, transcrição, `text-embedding-3-small`) |
| Banco | Supabase (Postgres + pgvector) |
| Buffer | Redis |
| Base de conhecimento | Google Drive e Google Sheets |
| CRM | Qualquer CRM com endpoint HTTP |
| Revisão | GitHub Actions + Claude Code |

## Como usar

Crie o banco com [`supabase/schema.sql`](supabase/schema.sql), configure as variáveis de [`.env.example`](.env.example) e importe os arquivos de [`workflows/`](workflows/) no n8n. Passo a passo em [`docs/instalacao.md`](docs/instalacao.md); prompts versionados em [`prompts/`](prompts/).

## Licença

[MIT](LICENSE).
