# Integrações

Guia de configuração das integrações externas. Para publicar a API, veja [DEPLOY.md](DEPLOY.md).

- [Pluggy (Open Finance)](#pluggy-open-finance)
- [Alexa](#alexa)
- [Alertas proativos por voz](#alertas-proativos-por-voz)
- [Como os alertas funcionam](#como-os-alertas-funcionam)
- [Push (FCM)](#push-fcm)
- [E-mail](#e-mail)

---

## Pluggy (Open Finance)

### Credenciais

1. Em [dashboard.pluggy.ai](https://dashboard.pluggy.ai), crie uma aplicação (o modo sandbox basta).
2. Copie o **Client ID** e o **Client Secret** para `PLUGGY_CLIENT_ID` e `PLUGGY_CLIENT_SECRET`.
3. No sandbox, use o conector **Pluggy Bank** com `user-ok` / `password-ok` (MFA `123456`).

### Fluxo de conexão

1. O app pede um *connect token*: `POST /consentimentos/connect-token`.
2. O app abre o Pluggy Connect (`flutter_pluggy_connect`). Ao concluir, o widget devolve `onSuccess({'item': {'id': ...}})`.
3. O app envia o `itemId`: `POST /consentimentos`. A API grava o `itemId` **criptografado** (AES-256-GCM) e um hash SHA-256 (usado para achar o usuário no webhook), cria a instituição e as contas e **enfileira a primeira sincronização**.

### Sincronização

- Janela de 90 dias, pelo endpoint `GET /v2/transactions` do Pluggy (paginação por cursor, via `fetchAllTransactions`). O endpoint antigo `GET /transactions` foi descontinuado e responde `410`.
- A direção do dinheiro vem do **sinal do valor**: negativo é despesa, positivo é receita. O campo `type` não serve: compras no cartão chegam como `CREDIT` com valor negativo. O valor é gravado em módulo.
- A sincronização atualiza o saldo das contas, categoriza e avalia as regras de alerta (veja [Como os alertas funcionam](#como-os-alertas-funcionam)).

### Webhook

O Pluggy **não assina** os eventos de item com HMAC: a autenticação é um **header personalizado**, definido ao cadastrar o webhook. O backend exige `x-webhook-secret` igual a `PLUGGY_WEBHOOK_SECRET`.

Cadastre com o script (ele pede o segredo num campo oculto, remove webhooks antigos que apontavam para túneis e testa a autenticação):

```bash
cd backend
bash scripts/registrar-webhook-pluggy.sh https://SUA-URL
```

Eventos cadastrados: `item/updated` e `item/created`. O payload traz `itemId` no nível superior; o backend localiza o usuário pelo hash e enfileira uma sincronização.

Para conferir à mão: com o segredo correto a rota responde `200`; sem ele ou com outro, `401`.

---

## Alexa

A skill é personalizada (invocação **"controle financeiro"**) e roda em uma função AWS Lambda. Ela não tem regra de negócio: chama a API do backend com o token do usuário vinculado, que só acessa `GET /contas/saldo`, `GET /transacoes/resumo-categorias` e `PATCH /auth/alexa-id`.

Frases: "abre controle financeiro", "pergunta pro controle financeiro qual é meu saldo", "…quanto gastei esse mês", "…como estão minhas finanças".

### Pré-requisitos

- Conta Amazon Developer (developer.amazon.com) e conta AWS.
- API publicada em HTTPS ([DEPLOY.md](DEPLOY.md)).
- Um app Alexa ou Echo na **mesma conta Amazon**, com idioma Português (Brasil).

### 1. Criar a skill e importar o modelo

1. Console da Alexa → **Create Skill** → idioma **Portuguese (BR)** → tipo **Custom** → hospedagem **Provision your own** → *Start from Scratch*.
2. **Build → Interaction Model → JSON Editor**: cole o conteúdo de `alexa-skill/models/pt-BR/pt-BR.json` → **Save Model** → **Build Model**.
3. Anote o **Skill ID** (**Build → Endpoint**).

### 2. Lambda

```bash
cd alexa-skill
npm install
npm run package        # gera alexa-skill/lambda.zip (código + dependências de produção)
```

Na AWS (**Lambda → Criar função → Criar do zero**, sem endpoint HTTP):

| Item | Valor |
|---|---|
| Runtime | Node.js 24.x |
| Código | enviar `lambda.zip` |
| Handler | `dist/index.handler` |
| Tempo limite | 10 segundos |
| Variável de ambiente | `API_BASE_URL` = URL pública da API, **sem barra no final** |
| Gatilho | *Alexa Skills Kit*, com a verificação do Skill ID ativada |

> O handler é assíncrono de propósito. O `.lambda()` do ASK SDK usa o estilo *callback*, que os runtimes novos da AWS (Node.js 24) não suportam: a função devolveria resposta vazia e a Alexa diria "Um problema ocorreu com a resposta da Skill".

Copie o **ARN** da função e cole em **Build → Endpoint → AWS Lambda ARN → Default Region**. A região do ARN usada neste projeto é `us-east-2`.

### 3. Account Linking

**Build → Account Linking**, ativando o vínculo, com **Auth Code Grant** (PKCE desligado) e:

| Campo | Valor |
|---|---|
| Web Authorization URI | `https://SUA-URL/oauth/authorize` |
| Access Token URI | `https://SUA-URL/oauth/token` |
| Client ID | o valor de `ALEXA_OAUTH_CLIENT_ID` |
| Client Secret | o valor de `ALEXA_OAUTH_CLIENT_SECRET` |
| Esquema de autenticação | **HTTP Basic** |
| Scope | `profile` |

Depois de salvar, o fim da página mostra os **Redirect URLs** (três endereços `https://…amazon.com/api/skill/link/<vendorId>`). Coloque-os em `ALEXA_REDIRECT_URIS`, separados por vírgula, e **reinicie a API**. O backend só aceita esses endereços exatos.

### 4. Vincular e testar

1. Crie sua conta no app **apontando para a API publicada** (o usuário precisa existir no mesmo banco que a Alexa consulta) e conecte uma conta no Pluggy.
2. Vincule pelo app Alexa (**Mais → Skills e Jogos → Suas Skills → Dev → controle financeiro**) ou pelo navegador (alexa.amazon.com → Skills → Suas Skills → Dev). Entre com o e-mail e a senha do FinanceControl.
3. No console, aba **Test** (modo *Development*): `abre controle financeiro`, `qual é meu saldo`.

O `alexaUserId` só é gravado na primeira abertura da skill.

### Se a vinculação falhar

O backend registra o motivo de cada recusa, sem segredos. Procure no log da API as linhas `[OAuth]`:

| Linha | Causa |
|---|---|
| nenhuma | a Alexa não chegou à API: confira as URLs do Account Linking e a `API_BASE_URL` da Lambda |
| `authorize recusado: client_id inválido` | o Client ID do console difere de `ALEXA_OAUTH_CLIENT_ID` |
| `authorize recusado: redirect_uri fora da lista` | falta o endereço em `ALEXA_REDIRECT_URIS` |
| `token recusado (invalid_client) … secret com N caractere(s)` | o segredo do console está errado (o correto tem o tamanho de `ALEXA_OAUTH_CLIENT_SECRET`) |
| `troca de código recusada: …` | código expirado (5 min), já usado, ou `redirect_uri` diferente |

Outros sintomas: *"E-mail ou senha incorretos"* na página de login significa que o usuário não existe **naquele** banco; HTTP 429 é o bloqueio de 5 tentativas (15 minutos). Os logs da Lambda ficam em **Monitor → CloudWatch**.

---

## Alertas proativos por voz

Opcional. Faz a Alexa avisar que há uma notificação (o anel do Echo acende). O evento `AMAZON.MessageAlert.Activated` **não lê o texto do alerta**: o conteúdo completo continua no app.

A página **Permissions** do console de uma skill personalizada **não tem** essa opção. É preciso usar a **ASK CLI**:

```bash
npm install -g ask-cli
ask configure                      # login no navegador; responda "n" para vincular conta AWS
ask smapi list-skills-for-vendor   # deve listar a skill
```

1. **Declarar a permissão e o evento no manifest.** Baixe o manifest, acrescente os dois blocos abaixo e envie de volta (o resto fica intacto; o Account Linking não faz parte do manifest):

   ```bash
   ask smapi get-skill-manifest -s SKILL_ID -g development > manifest.json
   ```

   ```json
   "permissions": [{ "name": "alexa::devices:all:notifications:write" }],
   "events": {
     "publications": [{ "eventName": "AMAZON.MessageAlert.Activated" }],
     "endpoint": { "uri": "<o mesmo ARN da Lambda>" }
   }
   ```

   ```bash
   ask smapi update-skill-manifest -s SKILL_ID -g development --manifest file:manifest.json
   ```

   O `endpoint` dentro de `events` é obrigatório; sem ele a API devolve `400`.

2. **Ler as credenciais da skill** (existem só depois do passo anterior; antes, o comando responde `404`):

   ```bash
   ask smapi get-skill-credentials -s SKILL_ID
   ```

   Coloque `clientId` e `clientSecret` em `ALEXA_CLIENT_ID` e `ALEXA_CLIENT_SECRET` e reinicie a API. O backend pede o token à Amazon com o escopo `alexa::proactive_events`.

3. **Estágio:** enquanto a skill estiver em desenvolvimento, mantenha `ALEXA_SKILL_STAGE=development` (os eventos vão para `/stages/development`). Use `live` depois de publicar.

4. **Cada usuário** precisa ativar as **notificações** da skill no app Alexa e abrir a skill uma vez.

5. Crie uma regra com o canal **Alexa** ou **Push + Alexa** para receber o aviso.

---

## Como os alertas funcionam

Cada sincronização avalia as regras ativas do usuário **sobre as transações novas** (as já existentes não disparam de novo).

| Tipo | Dispara quando |
|---|---|
| `TRANSACAO_GRANDE` | uma despesa nova passa do limite |
| `DESPESA_CATEGORIA` | uma despesa nova da categoria escolhida passa do limite |
| `SALDO_MINIMO` | o saldo da conta escolhida (exceto cartão de crédito) fica abaixo do limite; no máximo um alerta por conta e um aviso por regra a cada 24 h |
| `PIX_RECEBIDO` / `PIX_ENVIADO` | entra/sai um Pix novo (detectado pelo método de pagamento do Pluggy ou por "pix" na descrição), opcionalmente a partir de um valor |

- O limite precisa ser maior que zero (opcional nos alertas de Pix); a categoria é obrigatória em `DESPESA_CATEGORIA` e a conta em `SALDO_MINIMO`.
- Canais: `PUSH` (FCM), `ALEXA` (evento proativo) ou `AMBOS`. Cada canal só envia o que escolheu.
- Há no máximo uma notificação por regra e transação. A notificação é sempre gravada e aparece na central do app; o status vira `ENVIADO` quando o push é entregue.

---

## Push (FCM)

**Backend pronto, app pendente.** O backend envia o push quando há `FCM_SERVER_KEY` (JSON da conta de serviço do Firebase, puro ou em base64) e o aparelho registrou o token em `PATCH /auth/fcm-token`. Sem a chave, o envio fica desligado e o log avisa.

Falta no app: o pacote `firebase_messaging`, os arquivos `google-services.json` (Android) e `GoogleService-Info.plist` (iOS), o pedido de permissão e o registro do token. No iOS, o push exige uma chave APNs, isto é, **conta Apple Developer paga**.

---

## E-mail

**Não implementado.** O `MailService` só escreve o token de recuperação de senha no log (`[DEV] Recuperação de senha para …`). As variáveis `SMTP_*` do `.env.example` ainda não são lidas, e o app não tem tela de redefinição de senha. Falta escolher um provedor SMTP, enviar a mensagem e criar a tela.
