# FinanceControl — app (Flutter)

App móvel do FinanceControl: saldo consolidado, extrato, relatórios por categoria, regras de alerta, central de notificações, conexão de contas via Pluggy e biometria.

Visão geral do projeto, requisitos e arquitetura: [README da raiz](../README.md).

## Requisitos

- Flutter **3.47** ou superior (Dart 3.13+)
- Para iOS: Xcode e uma conta Apple (a gratuita basta para instalar no seu iPhone; o app expira em 7 dias)
- Para Android: Android Studio com um emulador

## Rodar

O endereço da API é definido **na hora do build**, com `--dart-define`. Um app já instalado guarda o endereço que tinha ao ser compilado: **para mudar de ambiente, reinstale**.

```bash
flutter pub get

# Emulador Android — o padrão http://10.0.2.2:3000 aponta para a API local do seu computador
flutter run -d emulator-5554

# Simulador iOS contra a API local
flutter run -d <id> --dart-define=API_BASE_URL=http://localhost:3000

# Contra a API publicada (necessário em aparelho físico)
flutter run -d <id> --dart-define=API_BASE_URL=https://SUA-URL
```

| Parâmetro | Para que serve |
|---|---|
| `API_BASE_URL` | Endereço da API |
| `PLUGGY_SANDBOX=true` | Mostra os conectores de teste (Pluggy Bank). Em debug já vem ligado; em `--release` é preciso informar |

Conectar o banco de teste: **Pluggy Bank**, usuário `user-ok`, senha `password-ok`, MFA `123456`.

### iPhone físico

1. Conecte, desbloqueie e confie no computador; ative o **Modo Desenvolvedor** (Ajustes → Privacidade e Segurança).
2. `open ios/Runner.xcworkspace` → *Runner* → **Signing & Capabilities** → marque *Automatically manage signing* e escolha o seu **Team**. Se o identificador estiver em uso, troque o *Bundle Identifier*.
3. Rode com `--release` para abrir o app pela tela inicial sem o computador:

```bash
flutter run -d <id-do-iphone> --release \
  --dart-define=API_BASE_URL=https://SUA-URL \
  --dart-define=PLUGGY_SANDBOX=true
```

O aparelho não alcança o `localhost` do computador, e o iOS bloqueia `http://` puro: use a API publicada (HTTPS). Em builds de debug no iOS 14+, o app só abre pelo Flutter ou pelo Xcode.

## Telas

| Aba | Conteúdo |
|---|---|
| Início | Saldo total, saldo por instituição, acesso às contas conectadas |
| Transações | Extrato com filtros (período, categoria, tipo, banco, valor), paginação, cache local e correção de categoria (toque na transação) |
| Relatórios | Despesas por categoria (este mês, mês anterior, 3 meses) e receitas × despesas por mês |
| Alertas | Notificações e acesso às regras de alerta |
| Perfil | Nome, e-mail, senha, biometria, regras de categorização, vínculo da Alexa (desvincular), sair e excluir conta |

Os dados de cada aba são recarregados ao abri-la.

## Comportamentos importantes

- **Sessão:** o app restaura a sessão ao abrir. Sem rede, mantém a sessão e usa o cache (saldo e extrato salvos no aparelho); se o servidor recusar a renovação, volta ao login.
- **Biometria:** bloqueia ao abrir e após 30 segundos em segundo plano; depois de 3 falhas (ou sem biometria no aparelho) exige a senha, o que encerra a sessão local. Ativar exige confirmar a biometria na hora. No Android usa `FlutterFragmentActivity` e um tema `AppCompat`; no iOS, `NSFaceIDUsageDescription`.
- **Erros de conexão:** login e cadastro mostram "Não foi possível conectar ao servidor" quando a API não responde, o que normalmente indica um app instalado com a URL errada.

## Testes

```bash
flutter analyze
flutter test          # 52 testes
```

Os testes cobrem restauração de sessão, biometria e tela de bloqueio, regras de alerta, relatórios e períodos. Os plugins nativos são substituídos por implementações falsas (`test/support/fakes.dart`).

## Estrutura

```
lib/
├── core/            # cliente HTTP (Dio, renovação de token), banco local, tema
└── features/        # auth, accounts, home, transactions, dashboard,
                     # alert_rules, notifications, main (navegação)
```

## Ainda não implementado

Nada além da configuração do Firebase para ativar o push (`--dart-define=FCM_ENABLED=true`; veja docs/INTEGRACOES.md).
