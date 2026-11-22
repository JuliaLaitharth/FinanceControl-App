# FinanceControl

Assistente financeiro pessoal com integração Open Finance (Pluggy), app Flutter, API NestJS e skill Alexa, com foco em LGPD.

> Projeto acadêmico — DVP v3.0 — Universidade de Passo Fundo

---

## Sumário

- [Visão geral](#visão-geral)
- [Estado atual dos requisitos](#estado-atual-dos-requisitos)
- [Arquitetura](#arquitetura)
- [Requisitos](#requisitos)
- [Configuração local](#configuração-local)
- [Publicação (deploy)](#publicação-deploy)
- [Variáveis de ambiente](#variáveis-de-ambiente)
- [API — endpoints](#api--endpoints)
- [Testes e CI](#testes-e-ci)
- [Integrações](#integrações)
- [Segurança e LGPD](#segurança-e-lgpd)
- [Limitações conhecidas e próximos passos](#limitações-conhecidas-e-próximos-passos)
- [Documentação](#documentação)

---

## Visão geral

| Camada | Tecnologia |
|---|---|
| Backend | NestJS 12 (ESM), PostgreSQL 16, Prisma 5, Redis 7, BullMQ 6 |
| App | Flutter 3.47 / Dart 3.13 — Riverpod (MVVM), Dio, sqflite, fl_chart, local_auth |
| Open Finance | Pluggy (SDK `pluggy-sdk` no backend, `flutter_pluggy_connect` no app) |
| Voz | Alexa Skill personalizada (ASK SDK v2) em AWS Lambda |
| Autenticação | JWT (access de 15 min) + refresh token rotativo de 30 dias, bcrypt (12 rounds) |
| Criptografia | AES-256-GCM em repouso para o `itemId` do Pluggy |
| Publicação | Docker (imagem de produção) no Railway; Render e Docker Compose como alternativas |
| CI | GitHub Actions (backend: lint e testes; Flutter: análise e testes) |

---

## Estado atual dos requisitos

Legenda: ✅ funcionando e verificado · ⚠️ parcial ou pendente.

| RF | Descrição | Estado |
|---|---|---|
| RF01 | Cadastro, login com bloqueio (5 falhas → 15 min), sessão restaurada ao abrir o app, biometria com fallback para senha | ✅ — recuperação de senha por e-mail (código de 8 caracteres, via Resend) |
| RF02 | Conexão de contas via Pluggy Connect | ✅ |
| RF03 | Saldo consolidado e cache local (SQLite) | ✅ |
| RF04 | Transações com paginação e filtros (período, categoria, tipo, conta, banco e valor) e sincronização | ✅ |
| RF05 | Categorização automática por palavras-chave, regras do usuário e correção manual no app | ✅ |
| RF06 | Regras de alerta (saldo mínimo por conta, transação grande, despesa por categoria, Pix recebido/enviado; canais Push, Alexa ou ambos) | ✅ |
| RF07 | Central de notificações no app e push (FCM) | ✅ central de notificações — **push no aparelho ⚠️**: o backend envia, mas o app ainda não integra o `firebase_messaging` |
| RF08 | Alexa: vínculo de conta (OAuth 2.0), saldo e gastos por voz | ✅ — alertas por voz ⚠️ configuração em andamento (ver [integrações](docs/INTEGRACOES.md#alertas-proativos-por-voz)) |
| RF09 | Relatórios: despesas por categoria (por período) e receitas × despesas por mês | ✅ |
| RF10 | LGPD: revogação de consentimento e exclusão total da conta | ✅ |
| RF11 | Perfil: editar nome, alterar e-mail, alterar senha, biometria, excluir conta | ✅ |

---

## Arquitetura

```
FinanceControl/
├── backend/                # API REST — NestJS (ESM)
│   ├── Dockerfile          # Imagem de produção (migrations + servidor)
│   ├── railway.toml        # Config do Railway (Root Directory = backend)
│   ├── prisma/             # Schema, migrations e seed
│   ├── scripts/            # start.sh e utilitários de operação
│   └── src/
│       ├── auth/           # JWT, sessões, bloqueio, biometria, perfil
│       ├── consentimento/  # Conexão Pluggy (connect token e itemId criptografado)
│       ├── conta/          # Contas e saldo consolidado
│       ├── transacao/      # Sincronização, filtros, resumos e categorização
│       ├── categoria/      # Categorias padrão (garantidas na subida)
│       ├── regra-alerta/   # Regras de alerta
│       ├── regra-categorizacao/
│       ├── notificacao/    # Central de notificações
│       ├── worker/         # Fila BullMQ (pluggy-sync) e avaliação das regras
│       ├── webhook/        # Webhooks do Pluggy
│       ├── oauth/          # Account Linking da Alexa
│       ├── alexa/          # Eventos proativos
│       ├── fcm/            # Push (Firebase Admin)
│       ├── lgpd/           # Exclusão total de dados
│       └── ...
├── app/                    # Flutter — MVVM + Riverpod
│   └── lib/features/
│       ├── auth/           # Login, cadastro, perfil, biometria
│       ├── accounts/       # Contas e conexão Pluggy
│       ├── home/           # Saldo consolidado
│       ├── transactions/   # Extrato
│       ├── dashboard/      # Relatórios
│       ├── alert_rules/    # Regras de alerta
│       ├── notifications/  # Central de notificações
│       └── main/           # Navegação por abas
├── alexa-skill/            # Skill: handlers, modelo de voz, manifest, script do pacote da Lambda
└── docs/                   # Documentação (ver abaixo)
```

Fluxo principal: o app chama a API; ao conectar uma conta, a API enfileira uma sincronização (BullMQ) que busca contas e transações no Pluggy, categoriza, avalia as regras de alerta e grava notificações. O webhook do Pluggy dispara novas sincronizações. A skill Alexa consulta a mesma API usando um token de escopo restrito.

---

## Requisitos

- **Node.js** 20 ou superior (o CI usa 20; a imagem Docker usa 22)
- **Docker** e **Docker Compose** (PostgreSQL e Redis locais)
- **Flutter** 3.47 ou superior (Dart 3.13+)
- Conta [Pluggy](https://pluggy.ai) (o sandbox basta)
- Opcionais: conta Amazon Developer + AWS (Alexa), projeto Firebase (push)

---

## Configuração local

### Backend

```bash
git clone https://github.com/JuliaLaitharth/FinanceControl-App.git
cd FinanceControl-App

# Banco e Redis
docker compose up -d db redis

# Variáveis de ambiente
cp backend/.env.example backend/.env      # edite com seus valores

cd backend
npm install
npx prisma migrate deploy                 # cria as tabelas
npx prisma db seed                        # categorias padrão (a API também as garante ao subir)
npm run start:dev                         # http://localhost:3000
```

Confirme com `curl http://localhost:3000/health`.

### App

O endereço da API é definido **na hora do build**, com `--dart-define`:

```bash
cd app
flutter pub get

# Emulador Android (o padrão 10.0.2.2:3000 aponta para o seu computador)
flutter run -d emulator-5554

# Simulador iOS
flutter run -d <id> --dart-define=API_BASE_URL=http://localhost:3000

# Contra a API publicada
flutter run -d <id> --dart-define=API_BASE_URL=https://SUA-URL
```

- Conectar o **Pluggy Bank** (sandbox) exige `PLUGGY_SANDBOX=true` em builds de release (em debug já vem ligado): `--dart-define=PLUGGY_SANDBOX=true`. Credenciais de teste: `user-ok` / `password-ok` (MFA `123456`).
- **iPhone físico:** o aparelho não enxerga o `localhost` do computador, e o iOS bloqueia `http://` puro; use a API publicada (HTTPS). A assinatura do app exige escolher um *Team* no Xcode (`ios/Runner.xcworkspace`).
- Como o endereço fica gravado no app, **mudar de ambiente exige reinstalar** com a nova URL.

---

## Publicação (deploy)

A API roda como container (`backend/Dockerfile`): espera o banco, aplica as migrations, garante as categorias padrão e inicia o servidor. O passo a passo completo, com a tabela de variáveis e a solução dos problemas mais comuns, está em **[docs/DEPLOY.md](docs/DEPLOY.md)**.

Resumo (Railway): conectar o repositório → *Root Directory* `backend` → PostgreSQL e Redis (modelos oficiais do Railway) → variáveis → *Generate Domain* → apontar Pluggy, Alexa e app para a URL pública.

Docker Compose local (inclui a API):

```bash
docker compose up --build -d
```

---

## Variáveis de ambiente

A lista comentada está em [`backend/.env.example`](backend/.env.example).

**Obrigatórias** (a API não sobe sem elas):

| Variável | Descrição |
|---|---|
| `DATABASE_URL` | Conexão PostgreSQL |
| `JWT_SECRET` | Segredo JWT (`openssl rand -hex 64`); **sem valor padrão** |
| `ENCRYPTION_KEY` | Chave AES-256-GCM: 64 caracteres hex (`openssl rand -hex 32`). Perdê-la torna ilegíveis os `itemId` já gravados |
| `PLUGGY_CLIENT_ID` / `PLUGGY_CLIENT_SECRET` | Credenciais da aplicação Pluggy |
| `PLUGGY_WEBHOOK_SECRET` | Valor que o backend exige no header `x-webhook-secret` dos webhooks |
| `REDIS_URL` **ou** `REDIS_HOST` + `REDIS_PORT` | Redis (`REDIS_URL` aceita usuário, senha e `rediss://`; tem prioridade). `REDIS_PASSWORD` também é aceita |

**Alexa** (sem estas, nenhuma vinculação é aceita):

| Variável | Descrição |
|---|---|
| `ALEXA_OAUTH_CLIENT_ID` / `ALEXA_OAUTH_CLIENT_SECRET` | Credenciais do Account Linking (você define e repete no console da Alexa) |
| `ALEXA_REDIRECT_URIS` | Redirect URLs do console, separadas por vírgula (comparação exata, só `https`) |
| `ALEXA_SKILL_STAGE` | `development` enquanto a skill não for publicada; `live` depois |
| `ALEXA_CLIENT_ID` / `ALEXA_CLIENT_SECRET` | Credenciais da skill para os alertas por voz (opcionais) |

**Opcionais:** `FCM_SERVER_KEY` (JSON da conta de serviço do Firebase, puro ou em base64; sem ele o push fica desligado), `PORT`, `NODE_ENV`, `MIGRATE_MAX_TENTATIVAS` e `MIGRATE_ESPERA_SEGUNDOS` (espera pelo banco na subida).

> `RESEND_API_KEY` e `MAIL_FROM` ativam o envio do código de recuperação de senha (veja [E-mail](docs/INTEGRACOES.md#e-mail)); sem a chave nenhum e-mail é enviado. `API_BASE_URL` é usada pela Lambda da Alexa, não pelo backend.

---

## API — endpoints

Todas as rotas `JWT` exigem `Authorization: Bearer <accessToken>`. Um token emitido para a Alexa só acessa `GET /contas/saldo`, `GET /transacoes/resumo-categorias` e `PATCH /auth/alexa-id`.

| Método | Rota | Auth | Descrição |
|---|---|---|---|
| GET | `/health` | — | Verificação de saúde (usada pelo Railway) |
| POST | `/auth/register` | — | Cadastro |
| POST | `/auth/login` | — | Login (5 falhas bloqueiam por 15 min) |
| POST | `/auth/refresh` | — | Renovar tokens (o refresh token rotaciona) |
| POST | `/auth/logout` | JWT | Encerrar sessão |
| POST | `/auth/forgot-password` | — | Solicitar redefinição (hoje só registra o token no log) |
| POST | `/auth/reset-password` | — | Redefinir senha |
| GET | `/auth/me` | JWT | Dados do usuário |
| PATCH | `/auth/biometria` | JWT | Ativar/desativar biometria |
| PATCH | `/auth/perfil` | JWT | Atualizar nome |
| PATCH | `/auth/email` | JWT | Alterar e-mail (reconfirma a senha) |
| PATCH | `/auth/senha` | JWT | Alterar senha |
| PATCH | `/auth/fcm-token` | JWT | Registrar token FCM do aparelho |
| GET | `/auth/alexa` | JWT | Informa se há conta Alexa vinculada |
| DELETE | `/auth/alexa` | JWT | Desvincular a Alexa (revoga os tokens) |
| PATCH | `/auth/alexa-id` | JWT | Registrar o ID da Alexa (feito pela skill) |
| DELETE | `/auth/conta` | JWT | Excluir conta e dados (LGPD) |
| POST | `/consentimentos/connect-token` | JWT | Token para abrir o Pluggy Connect |
| POST | `/consentimentos` | JWT | Registrar a conexão (`itemId`) |
| GET | `/consentimentos` | JWT | Listar conexões |
| DELETE | `/consentimentos/:id` | JWT | Revogar conexão |
| GET | `/contas` | JWT | Contas bancárias |
| GET | `/contas/saldo` | JWT | Saldo consolidado |
| GET | `/transacoes` | JWT | Extrato (`page`, `limit`, `de`, `ate`, `categoriaId`, `tipo`, `contaId`) |
| POST | `/transacoes/sincronizar` | JWT | Sincronização manual |
| GET | `/transacoes/resumo-categorias` | JWT | Despesas por categoria (`dataInicio`, `dataFim`; sem datas, o mês atual) |
| GET | `/transacoes/resumo-mensal` | JWT | Receitas e despesas por mês (`meses`) |
| PATCH | `/transacoes/:id/categoria` | JWT | Ajustar categoria manualmente |
| GET | `/categorias` | JWT | Categorias |
| GET/POST | `/regras-alerta` | JWT | Listar / criar regra |
| PATCH/DELETE | `/regras-alerta/:id` | JWT | Atualizar (inclui só `ativa`) / excluir |
| GET | `/notificacoes` | JWT | Listar notificações |
| GET | `/notificacoes/contagem` | JWT | Quantidade de não lidas |
| PATCH | `/notificacoes/:id/ler` | JWT | Marcar como lida |
| PATCH | `/notificacoes/ler-todas` | JWT | Marcar todas como lidas |
| GET/POST | `/regras-categorizacao` | JWT | Listar / criar regra de categorização |
| DELETE | `/regras-categorizacao/:id` | JWT | Excluir regra de categorização |
| GET | `/oauth/authorize` | — | Página de login do Account Linking (Alexa) |
| POST | `/oauth/authorize` | — | Autenticar e gerar o código |
| POST | `/oauth/token` | Basic | Trocar código por token / renovar |
| POST | `/webhooks/pluggy` | header | Webhook do Pluggy (`x-webhook-secret`) |

A coleção do Postman está em [`docs/FinanceControl.postman_collection.json`](docs/FinanceControl.postman_collection.json).

---

## Testes e CI

```bash
# Backend (124 testes, 15 suítes)
cd backend
npm test                 # unitários
npm run test:cov         # com cobertura
npm run lint

# App (48 testes)
cd app
flutter analyze
flutter test
```

O GitHub Actions roda o lint e os testes do backend e a análise e os testes do Flutter (Flutter 3.47.5) a cada push.

---

## Integrações

Guia de configuração de cada uma em **[docs/INTEGRACOES.md](docs/INTEGRACOES.md)**:

- **Pluggy** — credenciais, fluxo de conexão, sincronização e webhook.
- **Alexa** — skill, Lambda, Account Linking e alertas por voz.
- **Push (FCM) e e-mail** — estado atual e o que falta.

---

## Segurança e LGPD

Checklist completo, com o que está implementado e o que ainda é pendência, em **[docs/COMPLIANCE.md](docs/COMPLIANCE.md)**. Em resumo:

- Escopo **somente leitura**: nenhuma rota inicia pagamento ou transferência.
- Consentimento explícito: a conexão bancária só ocorre quando o usuário abre o Pluggy Connect.
- Exclusão total: `DELETE /auth/conta` revoga os itens no Pluggy e apaga os dados em cascata.
- Criptografia em repouso do `itemId` do Pluggy (AES-256-GCM); senhas com bcrypt; tokens de recuperação guardados só como hash.
- Auditoria das ações sensíveis (`LogAuditoria`, com IP e horário).
- Tokens da Alexa guardados só como hash SHA-256; `helmet`, limite de requisições por IP e `trust proxy`; container sem `root`.

---

## Limitações conhecidas e próximos passos

- Push no aparelho (FCM).
- Alertas por voz: o evento `MessageAlert` apenas avisa que há uma mensagem, sem ler o texto.
- Criptografar os tokens da Alexa guardados no banco.
- Pagamentos de fatura do cartão (valor positivo na conta do cartão) entram como receita nos relatórios.

---

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [docs/DEPLOY.md](docs/DEPLOY.md) | Publicação no Railway/Render e solução de problemas |
| [docs/INTEGRACOES.md](docs/INTEGRACOES.md) | Pluggy, Alexa, FCM e e-mail |
| [docs/COMPLIANCE.md](docs/COMPLIANCE.md) | LGPD e segurança |
| [docs/DECISOES.md](docs/DECISOES.md) | Decisões de arquitetura e escopo |
| [app/README.md](app/README.md) | Rodar, testar e instalar o app |
| [backend/README.md](backend/README.md) | Scripts, testes e operação do backend |
