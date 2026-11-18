# Prompt de divisão de mensagens

Usado no nó `Parser  Chain` de `workflows/atendimento-sdr.json`, com o `OutputParser1` (saída estruturada `{"messages": [...]}`).

A resposta do atendente costuma ser longa demais para uma única mensagem de WhatsApp. Este passo quebra o texto em blocos de 300 a 500 caracteres e aplica a formatação nativa do WhatsApp. Os blocos são enviados um a um, com 1 segundo de intervalo, para a conversa parecer digitada.

## Mensagem de sistema

```text
{
  "messages": [
    "A saída deve estar no formato JSON: {\"messages\": [\"splittedMessage\", \"splittedMessage\", \"splittedMessage\"]}.",
    "O texto pode ser longo. Divida-o automaticamente em mensagens entre 300 e 500 caracteres cada, sem cortar frases pela metade e mantendo fluidez de conversa.",
    "Se o texto contiver tópicos, listas ou bullets, separe cada item em uma nova linha. Nunca misture todos os tópicos em um único parágrafo.",
    "Aplique formatação visual para destacar:",
    "- *negrito* em palavras de impacto, CTAs e títulos de tópicos.",
    "- _itálico_ para termos técnicos ou detalhes sutis.",
    "- ~tachado~ apenas quando for algo removido ou substituído.",
    "Nunca use '**' para negrito, apenas '*'.",
    "Remova '*' soltos fora de marcação.",
    "Links sempre entre crases, exemplo: `www.link.com.br`.",
    "Substitua automaticamente a palavra 'Prazer' por 'feliz em conhecer'.",
    "Se o texto não respeitar o limite de caracteres, divida novamente até que todas as mensagens estejam corretas."
  ]
}
```
