# Checklist de Conformidade — LGPD e Segurança

> DVP v3.0 — FinanceControl — Universidade de Passo Fundo
> Atualizado: 2026-11-22

Legenda: ✅ implementado e verificado no código · ⚠️ parcial ou pendência · ❌ não implementado.

Este documento descreve **o que o código faz hoje**. Itens ⚠️ e ❌ estão reunidos em [Pendências](#7-pendências-de-conformidade).

---

## 1. LGPD — Lei Geral de Proteção de Dados (Lei nº 13.709/2018)

### 1.1 Base legal e finalidade

| Item | Status | Evidência |
|---|---|---|
| Coleta limitada à finalidade do serviço (Art. 6º, I) | ✅ | Coletados: nome, e-mail, senha (hash) e dados bancários lidos via Pluggy |
| Consentimento explícito antes de integrar conta bancária | ✅ | A conexão só ocorre quando o usuário abre o Pluggy Connect (`POST /consentimentos` recebe o `itemId` que o widget devolve) |
| Finalidade informada ao usuário | ⚠️ | A tela **Conectar conta** é o ponto de consentimento, mas não há texto de finalidade/política de privacidade no app |
| Dados de menores não coletados | ✅ | Sem campo de data de nascimento |

### 1.2 Direitos do titular

| Direito | Endpoint | Implementação |
|---|---|---|
| Acesso (Art. 18, II) | `GET /auth/me` | Retorna os dados cadastrais (nome, e-mail, biometria) |
| Revogação do consentimento (Art. 8º, §5º) | `DELETE /consentimentos/:id` | Revoga o item no Pluggy e marca o consentimento como revogado |
| Exclusão (Art. 18, VI) | `DELETE /auth/conta` | `LgpdService.excluirConta` revoga os itens no Pluggy (falha na revogação externa só gera aviso e a exclusão local prossegue), registra a auditoria e apaga os dados em cascata |
| Portabilidade (Art. 18, V) | — | ❌ Fora do escopo do DVP v3.0 |

### 1.3 Medidas técnicas

| Medida | Status | Detalhe |
|---|---|---|
| Criptografia em repouso | ✅ | O `itemId` do Pluggy é criptografado com AES-256-GCM (`EncryptionService`). Os tokens da Alexa (`VinculoAlexa`) ficam só como hash SHA-256 (não são legíveis) |
| Criptografia em trânsito | ✅ | HTTPS na API publicada (TLS do Railway); o app usa a URL `https` |
| Hash de senhas | ✅ | bcrypt, 12 rounds |
| Tokens de recuperação de senha | ✅ | Só o SHA-256 é gravado; expiram em 30 minutos e são de uso único |
| Escopo somente leitura no Open Finance | ✅ | Nenhuma rota inicia pagamento, transferência ou escrita financeira |
| Auditoria | ✅ | `LogAuditoria` registra ações sensíveis com IP e horário (cadastro, login, falhas e bloqueios, logout, troca/redefinição de senha, perfil, conexão e revogação de consentimento, consultas de saldo/contas, regras, sincronização e exclusão da conta). O `trust proxy` está ligado (1 salto; ajustável por `TRUST_PROXY_HOPS`), então o IP gravado é o do cliente |
| Retenção de logs | ✅ | Os registros de auditoria são apagados em cascata com a conta |

### 1.4 Incidentes

Em caso de incidente de segurança com dados pessoais, a ANPD deve ser notificada em prazo razoável (Art. 48 da LGPD). O contato do controlador é o e-mail institucional da equipe acadêmica do projeto.

---

## 2. Segurança da API

### 2.1 Autenticação e autorização

| Controle | Status | Detalhe |
|---|---|---|
| Access token de curta duração | ✅ | JWT de **15 minutos** |
| Refresh token rotativo | ✅ | Válido por 30 dias; a cada renovação o hash é substituído e o anterior deixa de valer. A sessão é guardada no banco (`Sessao`), o que permite revogação imediata |
| Bloqueio por tentativas | ✅ | 5 falhas → bloqueio de 15 minutos (`429`). Vale para o login do app **e** para o login da página de autorização da Alexa |
| Revogação de sessões | ✅ | Logout e alteração/redefinição de senha revogam as sessões |
| Resposta genérica no login | ✅ | "E-mail ou senha incorretos", com `bcrypt.compare` contra um hash falso quando o e-mail não existe (sem diferença de tempo) |
| Guard JWT nas rotas protegidas | ✅ | `JwtAuthGuard` nos controllers autenticados |
| Escopo restrito para o token da Alexa | ✅ | O token da Alexa só acessa `GET /contas/saldo`, `GET /transacoes/resumo-categorias` e `PATCH /auth/alexa-id`; as demais rotas respondem `403` |
| Isolamento entre usuários | ✅ | Consultas filtradas pelo usuário do token (`userId`) |
| `JWT_SECRET` obrigatório | ✅ | A API não sobe sem ele; não há valor padrão |
| Limite de requisições (rate limiting) | ✅ | 120 por minuto por IP em geral; login 20/min; cadastro, recuperação e redefinição de senha 10/min (`@nestjs/throttler`); o webhook do Pluggy é isento. Além do bloqueio de conta após 5 falhas de login |

### 2.2 Validação de entrada

| Controle | Status | Detalhe |
|---|---|---|
| `ValidationPipe` global | ✅ | `whitelist: true` e `transform: true`. **Todo campo de DTO precisa de decorator**: sem ele, o campo é descartado (um bug assim impediu a troca de token da Alexa até ser corrigido, e há teste cobrindo) |
| DTOs com `class-validator` | ✅ | |
| Validação de regras de negócio | ✅ | Ex.: regra de alerta exige limite maior que zero e categoria quando o tipo pede |
| SQL | ✅ | Prisma, com consultas parametrizadas; sem SQL manual |
| XSS | ✅ | A API é JSON, exceto a página de login do Account Linking, que é HTML: o `redirect_uri` só é aceito se estiver na lista exata e o `state` é escapado antes de ir para o `<script>` |
| Cabeçalhos de segurança (`helmet`) e CORS | ✅ | `helmet` ativo, com a CSP desligada (API JSON; a página de login da Alexa usa script embutido). CORS desligado de propósito: o cliente é um app nativo |

### 2.3 Segredos e configuração

| Controle | Status | Detalhe |
|---|---|---|
| Segredos só em variáveis de ambiente | ✅ | `ConfigModule`; nenhum segredo no código |
| Arquivos de segredo fora do Git | ✅ | `.env` e arquivos auxiliares (`.env.railway`, `.env.alexa-eventos`) no `.gitignore`; só o `.env.example` é versionado |
| Rotação de chaves | ⚠️ | Trocar o `JWT_SECRET` invalida as sessões e os vínculos da Alexa. A `ENCRYPTION_KEY` não tem rotação automática: trocá-la torna ilegíveis os `itemId` já gravados |
| Container sem privilégios | ✅ | A imagem executa como o usuário `node` |

### 2.4 Webhook do Pluggy

| Controle | Status | Detalhe |
|---|---|---|
| Autenticação | ✅ | O Pluggy **não assina** os eventos de item (sem HMAC). A autenticação é um header personalizado: o webhook é cadastrado com `x-webhook-secret` e o backend compara com `PLUGGY_WEBHOOK_SECRET` em tempo constante |
| Rejeição | ✅ | Segredo ausente ou errado → `401`; item sem consentimento correspondente é ignorado |

---

## 3. Open Finance — escopo somente leitura

- Nenhum endpoint inicia pagamento, transferência ou operação de escrita financeira.
- O Pluggy Connect é usado só para autenticar e **ler** contas e transações.
- A sincronização consulta os últimos 90 dias.

---

## 4. Alexa

| Item | Status | Detalhe |
|---|---|---|
| Account Linking OAuth 2.0 (Authorization Code) | ✅ | Código de uso único, válido por 5 minutos |
| Validação do cliente | ✅ | `client_id` e segredo (HTTP Basic) conferidos no `/oauth/token` |
| Endereços de retorno | ✅ | Só `https` e só os Redirect URLs listados em `ALEXA_REDIRECT_URIS`; sem lista, nada é aceito |
| Bloqueio de tentativas na página de login | ✅ | Mesmas regras do login do app |
| Tokens guardados no banco | ✅ | `accessToken` e `refreshToken` do `VinculoAlexa` ficam só como hash SHA-256 |
| Áudio e transcrições | ✅ | A skill não coleta nem armazena voz; o processamento é da Alexa |
| Alertas proativos | ✅ | Enviados apenas ao `alexaUserId` do usuário vinculado, e só se ele ativou as notificações |
| Revogação do vínculo | ✅ | Perfil → Alexa → Desvincular (`DELETE /auth/alexa`); o token deixa de valer na hora. A exclusão da conta também apaga o vínculo |

---

## 5. App

| Item | Status | Detalhe |
|---|---|---|
| Tokens no aparelho | ✅ | `flutter_secure_storage` (Keychain/Keystore) |
| Sessão | ✅ | Restaurada ao abrir; refresh renovado uma única vez por rodada de requisições; sessão expirada leva ao login |
| Biometria | ✅ | Bloqueia ao abrir e após 30 s em segundo plano; 3 falhas ou aparelho sem biometria exigem a senha (encerra a sessão local) |
| Cache local | ⚠️ | Transações ficam em SQLite sem criptografia; o cache é apagado no logout |

---

## 6. Dependências

Execute regularmente:

```bash
cd backend && npm audit
cd app && flutter pub outdated
```

Aplique correções de segurança antes de cada publicação.

---

## 7. Pendências de conformidade

| Prioridade | Pendência |
|---|---|
| Alta | Texto de finalidade e política de privacidade reais no app (a URL do manifest da Alexa ainda é um marcador) |
| Baixa | Rotação da `ENCRYPTION_KEY` (re-criptografar os `itemId`) |
| Baixa | Criptografar o cache SQLite do app |

---

## 8. Referências

- [Lei nº 13.709/2018 — LGPD](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)
- [ANPD — Autoridade Nacional de Proteção de Dados](https://www.gov.br/anpd)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [Pluggy — Documentação](https://docs.pluggy.ai)
- [Alexa — Account Linking](https://developer.amazon.com/en-US/docs/alexa/account-linking/account-linking-overview.html)
