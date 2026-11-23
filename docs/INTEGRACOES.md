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

**Código pronto no backend e no app; falta a configuração do Firebase** (feita fora do código). O push é **opt-in**: sem a configuração, o app roda normalmente e os alertas continuam aparecendo na aba **Alertas**.

Como funciona: o app (com `FCM_ENABLED=true`) inicia o Firebase, pede permissão, envia o token do aparelho para `PATCH /auth/fcm-token` e o backend envia o push (`FCM_SERVER_KEY`) quando uma regra com canal **Push** ou **Push + Alexa** dispara. Com o app aberto, o sistema não exibe a notificação; o app mostra um aviso na tela e atualiza o contador.

### 1. Projeto Firebase (comum aos dois sistemas)

1. Em [console.firebase.google.com](https://console.firebase.google.com) → **Adicionar projeto** (pode desativar o Google Analytics).
2. **Configurações do projeto → Contas de serviço → Gerar nova chave privada**. Isso baixa um JSON: é a credencial do **backend**.
3. No Railway (serviço da API → **Variables**), crie `FCM_SERVER_KEY` com o conteúdo do JSON (puro ou em base64: `base64 -i arquivo.json | pbcopy`). Não cole o JSON no chat nem o versione.

### 2. Android (não exige conta paga)

1. No Firebase → **Adicionar app → Android**; o nome do pacote é `com.financecontrol.finance_control`.
2. Baixe o `google-services.json` e salve em `app/android/app/google-services.json` (o arquivo é ignorado pelo Git; o plugin do Gradle só é aplicado quando ele existe).
3. Rode com o push ligado:

```bash
cd app
flutter run -d <id-android> --dart-define=API_BASE_URL=https://SUA-URL --dart-define=FCM_ENABLED=true
```

4. Aceite a permissão de notificações, crie uma regra com canal **Push** e dispare-a (por exemplo, uma regra de saldo mínimo com limite alto, depois uma sincronização). Se o app estiver fechado, a notificação aparece na bandeja do Android.

### 3. iOS (exige conta Apple Developer paga)

Push no iPhone precisa de uma chave **APNs**, que só existe na conta paga (US$ 99/ano). Com a conta gratuita o app continua funcionando sem push. Com a conta paga:

1. No portal Apple Developer, crie uma chave **APNs** (`.p8`) e envie-a no Firebase → **Configurações do projeto → Cloud Messaging → Apple app configuration**.
2. No Firebase, adicione um app iOS com o *Bundle Identifier* do Xcode e salve o `GoogleService-Info.plist` em `app/ios/Runner/` (adicione-o ao target *Runner* no Xcode).
3. No Xcode → *Runner → Signing & Capabilities*, adicione **Push Notifications** e **Background Modes → Remote notifications**.
4. Rode com `--dart-define=FCM_ENABLED=true`.

Sem o `FCM_ENABLED`, nenhuma chamada ao Firebase é feita; isso evita que o app caia no iOS por falta do `GoogleService-Info.plist`.

---

## E-mail

O app recupera a senha com um **código de 8 caracteres** (formato `ABCD-EFGH`) enviado por e-mail; vale 30 minutos e só pode ser usado uma vez (guardado como hash SHA-256). Fluxo: **Esqueci minha senha** → e-mail → **Já tenho o código** → código + nova senha. A resposta é a mesma exista ou não o e-mail, e a redefinição encerra todas as sessões.

O envio usa a API do [Resend](https://resend.com) (plano gratuito basta), configurada por duas variáveis:

| Variável | Valor |
|---|---|
| `RESEND_API_KEY` | chave criada em resend.com → API Keys (permissão *Sending access*) |
| `MAIL_FROM` | remetente, ex.: `FinanceControl <onboarding@resend.dev>` |

**Passo a passo**

1. Crie uma conta em resend.com e uma chave em **API Keys**.
2. No Railway, serviço da API → **Variables**, adicione `RESEND_API_KEY` (e `MAIL_FROM`, se quiser) e aguarde o redeploy.
3. Teste: no app, **Esqueci minha senha** com o e-mail cadastrado.

**Limitação importante:** sem um domínio verificado no Resend, o remetente `onboarding@resend.dev` só entrega para o **e-mail da sua própria conta Resend**. Para enviar a outros usuários é preciso verificar um domínio (Resend → Domains) e usá-lo em `MAIL_FROM`.

Sem `RESEND_API_KEY` nada é enviado: em desenvolvimento o código aparece no log (`[DEV] E-mail para …`); em produção sai só um aviso. Falhas do Resend são registradas no log e não mudam a resposta ao usuário.
