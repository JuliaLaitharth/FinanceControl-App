# FinanceControl — backend (NestJS)

API REST do FinanceControl: autenticação, integração com o Pluggy (Open Finance), sincronização de transações, regras de alerta, Account Linking da Alexa e exclusão de dados (LGPD).

Visão geral, requisitos e lista de endpoints: [README da raiz](../README.md). Publicação: [docs/DEPLOY.md](../docs/DEPLOY.md). Integrações: [docs/INTEGRACOES.md](../docs/INTEGRACOES.md).

## Stack

NestJS 12 (ESM), TypeScript 6, Prisma 5 + PostgreSQL 16, Redis 7 + BullMQ 6, `pluggy-sdk`, `firebase-admin`, Jest 30, oxlint.

## Desenvolvimento

```bash
docker compose up -d db redis          # na raiz do repositório
cp .env.example .env                   # edite os valores

npm install
npx prisma migrate deploy              # cria as tabelas
npx prisma db seed                     # categorias padrão (a API também as garante ao subir)
npm run start:dev                      # http://localhost:3000
```

Confirme com `curl http://localhost:3000/health`. Variáveis de ambiente: [`.env.example`](.env.example) (descrição na seção correspondente do README da raiz).

> Suba **uma única instância** do `start:dev`. Duas instâncias disputam a porta 3000 (`EADDRINUSE`); confira com `lsof -nP -iTCP:3000 -sTCP:LISTEN`.

## Scripts

| Comando | O que faz |
|---|---|
| `npm run start:dev` | Servidor com recarga automática |
| `npm run build` / `npm run start:prod` | Compila e roda `dist/main` |
| `npm test` | Testes unitários (Jest com `--experimental-vm-modules`) |
| `npm run test:cov` | Testes com cobertura |
| `npm run lint` | oxlint |

> Os testes só rodam pelo `npm test`: o Jest precisa da flag `--experimental-vm-modules` por causa do ESM. Chamar `npx jest` direto falha.

Os testes usam um mock do Prisma (`src/test-utils/prisma.mock.ts`), então **não** dependem de banco. Estado atual: 124 testes em 15 suítes.

## Estrutura

```
prisma/              schema, migrations e seed
scripts/             start.sh (espera o banco e aplica as migrations) e utilitários
src/
├── auth/            JWT, sessões, bloqueio de login, perfil, biometria
├── consentimento/   conexão Pluggy (itemId criptografado)
├── conta/           contas e saldo consolidado
├── transacao/       sincronização, filtros, resumos, categorização
├── categoria/       categorias padrão (garantidas na subida)
├── regra-alerta/    regras de alerta (validação e canais)
├── regra-categorizacao/
├── notificacao/     central de notificações
├── worker/          fila pluggy-sync e avaliação das regras
├── webhook/         webhooks do Pluggy
├── oauth/           Account Linking da Alexa
├── alexa/           eventos proativos
├── fcm/             push (Firebase Admin)
├── lgpd/            exclusão total de dados
├── redis/           parser de REDIS_URL
└── ...
```

## Fila de sincronização

O job `pluggy-sync` (BullMQ, 3 tentativas com espera exponencial) é criado quando uma conta é conectada e quando chega um webhook do Pluggy. Ele sincroniza contas e transações (90 dias), categoriza e avalia as regras de alerta **sobre as transações novas**.

## Scripts de operação (`scripts/`)

| Script | Uso |
|---|---|
| `start.sh` | Comando de subida do container. Repete `prisma migrate deploy` até o banco responder (`MIGRATE_MAX_TENTATIVAS`, padrão 24, e `MIGRATE_ESPERA_SEGUNDOS`, padrão 5) e inicia o servidor |
| `registrar-webhook-pluggy.sh` | `bash scripts/registrar-webhook-pluggy.sh https://SUA-URL` — cadastra os webhooks do Pluggy; o segredo é pedido em campo oculto |
| `testar-login.sh` | `bash scripts/testar-login.sh https://SUA-URL` — verifica se um e-mail/senha existem naquele backend (cada erro conta para o bloqueio de login) |

## Docker

```bash
docker build -t financecontrol-api .
```

A imagem aplica as migrations ao iniciar e depende de `DATABASE_URL`, `REDIS_URL` (ou `REDIS_HOST`) e das demais variáveis obrigatórias. Executa como `root` (melhoria pendente).

## Observação

Na criação de DTOs, **todo campo precisa de um decorator** do `class-validator`: o `ValidationPipe` global usa `whitelist: true` e descarta o que não tiver. Há um teste (`oauth.dto.spec.ts`) que protege os DTOs do OAuth.
