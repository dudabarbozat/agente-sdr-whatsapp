# Prompt de extração de dados do lead

Usado no nó `Basic LLM Chain1` de `workflows/atendimento-sdr.json` (no momento do encaminhamento) e no `Basic LLM Chain` de `workflows/reenvio-manual-crm.json`.

Recebe o histórico completo da conversa (tabela `chat_messages`) e devolve os campos estruturados que vão para `dados_cliente` e para o CRM. O formato da saída é fixado pelo `Structured Output Parser`:

```json
{
  "nome": "string",
  "interesse": "string",
  "tipo_imovel": "string",
  "regiao": "string",
  "faixa_valor": "string",
  "email": "string",
  "telefone": "string",
  "resumo_conversa": "string"
}
```

## Prompt

```text
Analise a conversa abaixo entre o agente (Lia) e o cliente.

Sua tarefa:
1. Extraia as seguintes informações quando presentes na conversa:
   - Nome completo do cliente
   - Interesse (comprar, alugar ou anunciar imóvel)
   - Tipo de imóvel (casa, apartamento, terreno, sala comercial etc.)
   - Região ou bairro de interesse
   - Faixa de valor ou orçamento
   - Email (se mencionado)
   - Telefone: {{ TELEFONE }}
2. Escreva um resumo conciso (2-3 frases) do que o cliente procura e de qualquer restrição mencionada (prazo, financiamento, garantia).
3. Retorne APENAS os dados estruturados solicitados, sem comentários adicionais.

Se uma informação não estiver presente na conversa, retorne string vazia para aquele campo.

Conversa:
{{ $json.texto }}
```

`{{ TELEFONE }}` é substituído pela expressão do telefone de cada workflow.
