# Checklist de revisão

Complementa a revisão diária automática. Serve para revisões manuais e para diagnóstico quando o time reportar problema.

## Semanal

### Funil
- [ ] Conversas iniciadas no WhatsApp
- [ ] Leads qualificados (Nível 2) e encaminhados
- [ ] Leads que chegaram ao CRM
- [ ] Perda entre encaminhado e CRM, e motivo (erro técnico, campo vazio, credencial)

### Agente
- [ ] Tom e regras do prompt respeitados nas conversas amostradas
- [ ] Perguntas recorrentes sem resposta na base de conhecimento
- [ ] Taxa de resposta aos passos de nutrição
- [ ] Necessidade de nova versão do prompt (registrar em `prompts/`)

## Sob demanda

Quando um lead "sumiu", verificar nesta ordem:
1. A execução do workflow no n8n terminou com erro? Em qual nó?
2. A conversa está em `chat_messages`? (a mensagem chegou ao fluxo)
3. `dados_cliente.atendimento_ia` está `pause`? (houve encaminhamento ou humano assumiu)
4. O nó `Enviar Lead ao CRM` executou? Qual foi o status HTTP?
5. Os campos obrigatórios estavam preenchidos no momento do envio?

Leads que ficaram presos podem ser reenviados com `workflows/reenvio-manual-crm.json`.
