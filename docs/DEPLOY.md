# Publicar o backend

O backend sobe como container (`backend/Dockerfile`). Ao iniciar, o `scripts/start.sh`:

1. aguarda o banco responder e aplica as migrations (`prisma migrate deploy`), tentando de novo a cada 5 s por até 24 vezes;
2. inicia o servidor, que garante as 14 categorias padrão (idempotente).

Precisa de **PostgreSQL** e **Redis**. O caminho validado é o **Railway**; o `render.yaml` existe como alternativa, mas **não foi testado**.

> Use um serviço sempre ligado: o Pluggy envia webhooks e a Alexa espera resposta em poucos segundos. Planos gratuitos que hibernam não servem. Confira os preços atuais antes de contratar.

## Railway

### 1. Projeto e serviços

1. railway.com → login com GitHub → **New Project → Deploy from GitHub repo** → escolha o repositório. O primeiro deploy **falha** (sem banco nem variáveis): é esperado.
2. No serviço da API: **Settings → Root Directory = `backend`**. O `backend/railway.toml` já define o Dockerfile e o healthcheck (`/health`).
3. **+ Create → Database → Add PostgreSQL** e **+ Create → Database → Add Redis**, usando os **modelos oficiais do Railway**.

> **Cuidado com a importação automática.** O Railway pode sugerir serviços a partir do `render.yaml`. Isso já criou um "Redis" que era na verdade um PostgreSQL e um banco que não aceitava conexões. Se aparecerem serviços importados, confira a imagem de cada um (um Redis tem as variáveis `REDIS_URL`/`REDISHOST`; um PostgreSQL tem `PGHOST`/`DATABASE_URL`) e, na dúvida, apague e crie de novo pelos modelos oficiais (um banco vazio não perde nada).

### 2. Variáveis da API (aba Variables → Raw Editor)

| Variável | Valor |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (referência; use o nome que aparece no seu canvas) |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` (idem) |
| `JWT_SECRET` | novo: `openssl rand -hex 64` |
| `ENCRYPTION_KEY` | novo: `openssl rand -hex 32` (64 caracteres). **Guarde uma cópia: perdê-la torna ilegíveis os `itemId` do Pluggy** |
| `PLUGGY_CLIENT_ID` / `PLUGGY_CLIENT_SECRET` | do dashboard do Pluggy |
| `PLUGGY_WEBHOOK_SECRET` | novo: `openssl rand -hex 32` |
| `ALEXA_OAUTH_CLIENT_ID` / `ALEXA_OAUTH_CLIENT_SECRET` | os mesmos do Account Linking no console da Alexa |
| `ALEXA_REDIRECT_URIS` | os Redirect URLs do console, separados por vírgula |
| `ALEXA_SKILL_STAGE` | `development` (use `live` só depois de publicar a skill) |
| `ALEXA_CLIENT_ID` / `ALEXA_CLIENT_SECRET` | opcionais: alertas por voz ([INTEGRACOES.md](INTEGRACOES.md#alertas-proativos-por-voz)) |
| `FCM_SERVER_KEY` | opcional: conta de serviço do Firebase |

Pontos de atenção:

- **Não defina `PORT`.** O Railway injeta a porta; um valor herdado de outra plataforma atrapalha.
- `${{…}}` são **referências**: digite assim, com chaves duplas, ou use o seletor de referência. Se o serviço do banco ainda estava sendo criado quando a API subiu, o valor pode ter resolvido para vazio: faça um novo deploy.
- Nunca cole segredos em chats ou tickets. Gere-os localmente e cole só no painel.

### 3. Domínio público

**Settings → Networking → Generate Domain**. Confira:

```bash
curl https://SUA-URL/health     # {"status":"ok","uptime":...}
```

### 4. Acompanhar o deploy

**Deployments → View logs → Deploy Logs.** O esperado, em ordem: `Applying migration …` (6 vezes), `Nest application successfully started` e o deploy ficar **Active**. Cada push no `main` dispara um novo deploy (a API reinicia por 1 a 2 minutos).

### 5. Apontar as integrações para a URL definitiva

| Onde | O que trocar |
|---|---|
| Pluggy | cadastrar o webhook: `bash backend/scripts/registrar-webhook-pluggy.sh https://SUA-URL` |
| Lambda da Alexa | variável `API_BASE_URL` |
| Console da Alexa → Account Linking | Authorization URI e Access Token URI → **Save** |
| App | reinstalar com `--dart-define=API_BASE_URL=https://SUA-URL` |

Detalhes de cada uma em [INTEGRACOES.md](INTEGRACOES.md).

### 6. Verificação final

```bash
# o usuário existe no banco publicado? (campo de senha oculto)
bash backend/scripts/testar-login.sh https://SUA-URL
```

Cadastre-se no app, conecte o Pluggy Bank, veja saldo e relatórios, vincule a Alexa e pergunte o saldo.

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| Build passa, mas o healthcheck falha | A aplicação caiu ao iniciar. Abra o **Deploy Logs** (não o Build Logs) |
| `Environment variable not found: DATABASE_URL` ou "resolved to an empty string" | Variável ausente ou referência para um serviço que não existe/ainda não estava pronto: corrija e faça novo deploy |
| `P1001: Can't reach database server` | O banco não responde. O `start.sh` repete por cerca de 2 minutos; se persistir, o serviço do banco está com problema: recrie-o pelo modelo oficial |
| `Config key "…" does not exist` | Falta uma variável obrigatória (o log diz qual) |
| `ECONNREFUSED`/`NOAUTH` do Redis | `REDIS_URL` aponta para o serviço errado ou antigo |
| A URL pública responde `404 Application not found` | Não há deploy ativo; veja o último deploy |
| Cadastro funciona no app, mas a Alexa diz "E-mail ou senha incorretos" | O app foi instalado com outra URL: o usuário está em outro banco. Reinstale o app com a URL publicada |

## Render (não validado)

O `render.yaml` descreve a API (plano `starter`, pois o `free` hiberna), um PostgreSQL e um Redis (`keyvalue`, com `noeviction`, exigido pelo BullMQ). Conecte o repositório em **New → Blueprint**, preencha os segredos marcados como `sync: false` e confira o resultado: o blueprint não foi executado de fato. O plano `free` do PostgreSQL expira; use um plano pago em produção.

## Docker Compose

Para rodar a API e as dependências localmente em container:

```bash
docker compose up --build -d     # lê backend/.env; usa o banco e o Redis do compose
```

## Cuidados

- O banco publicado começa **vazio**. Os dados de desenvolvimento não são migrados.
- Trocar o `JWT_SECRET` invalida os tokens existentes, inclusive o vínculo da Alexa (é preciso vincular de novo).
- Use **uma única instância** da API (as categorias padrão são garantidas na subida).
