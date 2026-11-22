# Decisões de Arquitetura e Escopo

> Registra ambiguidades resolvidas e escolhas feitas durante o desenvolvimento, conforme exigido pelo DVP (regra 6).
> Atualizado: 2026-11-22. Cada decisão indica a **situação atual** no código quando ela difere do plano original.

---

## D01 — Localização da Alexa Skill

**Decisão:** a skill fica em `alexa-skill/`, como pacote Node.js independente dentro do monorepo, e não como módulo NestJS.

**Motivo:** o ASK SDK exige um handler próprio para a Lambda da Alexa. Isolar facilita o deploy separado. Os dados vêm da API REST do backend, mantendo a regra de negócio em um único ponto (DVP §5).

**Situação atual:** em uso. O pacote da Lambda é gerado com `npm run package`.

---

## D02 — Um alerta de saldo mínimo por conta

**Decisão original:** impedir mais de um alerta de saldo mínimo **por conta**, validando no serviço (o modelo `RegraAlerta` não tem `contaId`).

**Situação atual: implementado.** `RegraAlerta` tem `contaId` (migration `20261122000001`); o serviço exige uma conta ativa do usuário no saldo mínimo e responde `409` se já houver alerta para a conta. O aviso continua limitado a **um a cada 24 h por regra**. Regras antigas (sem conta) seguem avaliando todas as contas que não sejam cartão até serem editadas.

---

## D03 — RF11 (Gerenciar Perfil): escopo mínimo viável

**Decisão original:** alterar nome, **e-mail** (com reconfirmação de senha), senha, biometria e excluir conta (LGPD). Sem foto de perfil nem preferências de idioma/tema.

**Situação atual:** implementados nome, e-mail (com reconfirmação de senha, `PATCH /auth/email`), senha, biometria e exclusão de conta.

---

## D04 — Criptografia em repouso (AES-256-GCM)

**Decisão original:** criptografar `itemIdPluggy` e também `access_token`/`refresh_token` do `VinculoAlexa`, com `EncryptionService` e a chave em `ENCRYPTION_KEY`.

**Situação atual: parcial.** Só o `itemIdPluggy` é criptografado (e um hash SHA-256 dele permite achar o usuário no webhook e impedir conexão duplicada). **Os tokens da Alexa ficam em texto no banco**: pendência de segurança registrada em [COMPLIANCE.md](COMPLIANCE.md).

---

## D05 — Hash falso no login

**Decisão:** quando o e-mail não existe, o `AuthService` executa `bcrypt.compare` contra um hash pré-computado antes de responder, para que o tempo seja igual ao de uma senha errada.

**Motivo:** evitar que se distinga "e-mail inexistente" de "senha errada" pela latência (timing attack). O DVP exige a resposta genérica "E-mail ou senha incorretos".

---

## D06 — Sessão persistida em banco (`Sessao`)

**Decisão:** o refresh token é guardado como hash SHA-256 em `Sessao` (e não só no JWT), o que permite revogação imediata no logout e na troca de senha.

**Motivo:** o DVP exige que o logout descarte os tokens e que a redefinição de senha invalide as sessões anteriores.

---

## D07 — Transações pelo endpoint v2 do Pluggy e direção pelo sinal do valor

**Decisão:** buscar transações com `GET /v2/transactions` (paginação por cursor, `fetchAllTransactions`) e definir **receita ou despesa pelo sinal do valor**, gravando o valor em módulo.

**Motivo:** o endpoint antigo `GET /transactions` foi descontinuado (`410`). Além disso, o campo `type` é enganoso: compras no cartão de crédito chegam como `CREDIT` com valor **negativo**, e seriam contadas como receita.

**Consequência conhecida:** um pagamento de fatura (valor positivo na conta do cartão) entra como receita nos relatórios.

---

## D08 — Webhook do Pluggy autenticado por header personalizado

**Decisão:** autenticar o webhook com um header `x-webhook-secret` definido ao cadastrá-lo, comparado em tempo constante com `PLUGGY_WEBHOOK_SECRET`.

**Motivo:** o Pluggy não assina os eventos de item com HMAC; a documentação prevê headers personalizados. O plano original (validar `x-pluggy-signature`) fazia o webhook responder `401` sempre.

---

## D09 — Canais de alerta: Push, Alexa ou ambos

**Decisão:** os canais de uma regra são `PUSH`, `ALEXA` e `AMBOS`. O canal `EMAIL` foi removido.

**Motivo:** o DVP fala em push e Alexa; o `EMAIL` nunca enviou e-mail, e o worker enviava à Alexa independentemente do canal. Agora cada canal envia só o que foi escolhido. O alerta de saldo mínimo ignora contas de cartão (o saldo do cartão é negativo por natureza).

---

## D10 — Handler assíncrono da Lambda e nome de invocação

**Decisão:** exportar `handler = (event, context) => skill.invoke(event, context)` em vez do `.lambda()` do SDK, e usar a invocação **"controle financeiro"**.

**Motivo:** o `.lambda()` devolve um handler no estilo *callback*, que o runtime Node.js 24 da AWS não suporta (resposta vazia). "Finance control" era mal reconhecido em português.

---

## D11 — Account Linking da Alexa: seguro por padrão

**Decisão:** o OAuth só aceita vinculação com `client_id`/segredo configurados e `redirect_uri` na lista exata `ALEXA_REDIRECT_URIS` (só `https`); a página de login tem o mesmo bloqueio de tentativas do app; o `state` é escapado.

**Motivo:** `/oauth/authorize` é público, e um `redirect_uri` livre permitiria roubar o código de acesso. Sem a configuração, nada é aceito.

---

## D12 — Alertas proativos pela ASK CLI

**Decisão:** declarar a permissão `alexa::devices:all:notifications:write` e o evento `AMAZON.MessageAlert.Activated` no manifest pela ASK CLI e ler as credenciais com `ask smapi get-skill-credentials`.

**Motivo:** o console de uma skill personalizada não tem essa opção. Limitação conhecida: o evento só avisa que há uma mensagem e não lê o texto.

---

## D13 — Publicação: espera pelo banco e categorias na subida

**Decisão:** o container usa `scripts/start.sh`, que repete as migrations até o banco responder (24 tentativas de 5 s), e a API garante as categorias padrão ao iniciar.

**Motivo:** em plataformas como o Railway o banco pode ainda não estar pronto quando o container nasce, e um banco novo não passa pelo seed manual.

---

## D14 — Sessão e biometria no app

**Decisão:** o app restaura a sessão ao abrir; requisições simultâneas com `401` compartilham **uma** renovação (o refresh token rotaciona); sem rede, a sessão é mantida; o bloqueio por biometria ocorre ao abrir e após 30 s em segundo plano, e 3 falhas exigem a senha.

**Motivo:** requisitos de RF01 e rotação do refresh token, que derrubava o usuário quando várias requisições renovavam ao mesmo tempo.
