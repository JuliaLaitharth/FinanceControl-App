# Publicar o backend (Railway)

O backend sobe como container (`backend/Dockerfile`): roda as migrations, garante as
categorias padrão e inicia o servidor. Precisa de **PostgreSQL** e **Redis**.

> Um serviço sempre ligado é necessário: o Pluggy envia webhooks e a Alexa espera
> resposta em poucos segundos. Planos gratuitos que hibernam não servem. Confira os
> preços atuais antes de contratar.

## 1. Projeto e serviços

1. railway.com → entre com o GitHub → **New Project → Deploy from GitHub repo** → escolha este repositório.
2. No serviço criado: **Settings → Root Directory = `backend`**. O `backend/railway.toml` já define Dockerfile e healthcheck (`/health`).
3. **+ New → Database → PostgreSQL** e **+ New → Database → Redis**.

## 2. Variáveis do serviço da API (aba Variables)

| Variável | Valor |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (referência ao banco) |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` (referência ao Redis) |
| `JWT_SECRET` | novo: `openssl rand -hex 64` |
| `ENCRYPTION_KEY` | novo: `openssl rand -hex 32` (64 caracteres). **Guarde uma cópia: perdê-la torna ilegíveis os itemIds do Pluggy já gravados** |
| `PLUGGY_CLIENT_ID` / `PLUGGY_CLIENT_SECRET` | do dashboard do Pluggy |
| `PLUGGY_WEBHOOK_SECRET` | novo, forte: `openssl rand -hex 32` |
| `API_BASE_URL` | URL pública do passo 3 |
| `ALEXA_OAUTH_CLIENT_ID` / `ALEXA_OAUTH_CLIENT_SECRET` | os mesmos do console da Alexa (Account Linking) |
| `ALEXA_REDIRECT_URIS` | os 3 Redirect URLs do console, separados por vírgula |
| `ALEXA_SKILL_STAGE` | `development` (use `live` só depois de publicar a skill) |
| `ALEXA_CLIENT_ID` / `ALEXA_CLIENT_SECRET` | de *Permissions → Send Alexa Events* (alertas por voz) |
| `FCM_SERVER_KEY` | JSON da conta de serviço do Firebase em base64 (push) |

O Railway injeta `PORT` sozinho. Não defina `JWT_SECRET` igual ao de desenvolvimento.

## 3. Domínio público

**Settings → Networking → Generate Domain**. Anote a URL (`https://….up.railway.app`),
preencha `API_BASE_URL` com ela e confira:

```bash
curl https://SUA-URL/health   # {"status":"ok",...}
```

## 4. Apontar as integrações para a URL definitiva

| Onde | O que trocar |
|---|---|
| Lambda da Alexa | variável `API_BASE_URL` |
| Console da Alexa → Account Linking | Authorization URI e Access Token URI → **Save** |
| Pluggy | apagar o webhook antigo e cadastrar `https://SUA-URL/webhooks/pluggy` com o header `x-webhook-secret` = `PLUGGY_WEBHOOK_SECRET` |
| App | `flutter run … --dart-define=API_BASE_URL=https://SUA-URL` |

## Observações

- O banco de produção começa **vazio**: usuários se cadastram de novo e reconectam os bancos.
  Os dados de desenvolvimento ficam só na sua máquina.
- Trocar o `JWT_SECRET` invalida vínculos da Alexa existentes: é preciso vincular de novo.
- O Dockerfile roda `prisma migrate deploy` a cada subida; migrations novas são aplicadas sozinhas.
- Use **uma única instância** da API (as categorias padrão são garantidas na subida).
