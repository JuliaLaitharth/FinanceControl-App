import 'package:flutter/material.dart';

/// Texto de finalidade e direitos do titular (LGPD, Lei 13.709/2018).
/// Usado como termo de consentimento antes de conectar uma conta e como tela
/// informativa no Perfil.
class PrivacidadeConteudo extends StatelessWidget {
  const PrivacidadeConteudo({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(t, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );
    Widget item(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text(t)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titulo('Para que usamos seus dados'),
        const Text(
          'O FinanceControl reúne saldos e transações das suas contas para mostrar seu saldo '
          'consolidado, extrato, relatórios por categoria e avisar você por alertas (no celular e, '
          'se você vincular, pela Alexa). Usamos os dados somente para isso.',
        ),
        titulo('O que coletamos'),
        item('Cadastro: nome, e-mail e senha (guardada apenas como hash).'),
        item('Dados bancários lidos pelo Open Finance: contas, saldos e transações.'),
        item('Registros de acesso (data, hora e IP) para segurança e auditoria.'),
        titulo('Como o acesso ao banco funciona'),
        item('Sua senha bancária é digitada somente na janela do agregador Pluggy; o app nunca a recebe.'),
        item('O acesso é somente de leitura: o app não faz pagamentos nem transferências.'),
        item('O consentimento vale por 1 ano e é registrado com data e validade.'),
        titulo('Seus direitos'),
        item('Revogar o consentimento a qualquer momento em Contas → Desconectar (os dados da conta são apagados).'),
        item('Excluir sua conta e todos os seus dados em Perfil → Excluir minha conta.'),
        item('Consultar e corrigir seus dados cadastrais em Perfil.'),
        titulo('Compartilhamento'),
        const Text(
          'Não vendemos nem compartilhamos seus dados com terceiros, exceto os provedores '
          'necessários ao serviço: Pluggy (leitura bancária), Firebase (notificações no celular), '
          'Amazon Alexa (se você vincular) e o serviço de e-mail usado na recuperação de senha.',
        ),
      ],
    );
  }
}

/// Tela informativa (Perfil → Privacidade e consentimento).
class PrivacidadeScreen extends StatelessWidget {
  const PrivacidadeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacidade e consentimento')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: PrivacidadeConteudo(),
        ),
      );
}
