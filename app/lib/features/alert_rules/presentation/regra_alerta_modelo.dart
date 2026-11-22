import 'package:intl/intl.dart';

/// Tipos de regra aceitos pelo backend (`tipoEvento`).
enum TipoRegra {
  saldoMinimo('SALDO_MINIMO', 'Saldo mínimo', 'Avisa quando o saldo de uma conta ficar abaixo do limite.'),
  transacaoGrande('TRANSACAO_GRANDE', 'Transação grande', 'Avisa quando uma despesa passar do limite.'),
  despesaCategoria('DESPESA_CATEGORIA', 'Despesa por categoria', 'Avisa quando uma despesa de uma categoria passar do limite.'),
  pixRecebido('PIX_RECEBIDO', 'Pix recebido', 'Avisa quando você receber um Pix (opcionalmente a partir de um valor).'),
  pixEnviado('PIX_ENVIADO', 'Pix enviado', 'Avisa quando você enviar um Pix (opcionalmente a partir de um valor).');

  const TipoRegra(this.codigo, this.titulo, this.descricao);
  final String codigo;
  final String titulo;
  final String descricao;

  bool get ehPix => this == pixRecebido || this == pixEnviado;

  static TipoRegra de(String? codigo) => TipoRegra.values.firstWhere(
        (t) => t.codigo == codigo,
        orElse: () => TipoRegra.transacaoGrande,
      );
}

/// Canais de notificação aceitos pelo backend (`canal`).
enum CanalRegra {
  push('PUSH', 'Push'),
  alexa('ALEXA', 'Alexa'),
  ambos('AMBOS', 'Push + Alexa');

  const CanalRegra(this.codigo, this.rotulo);
  final String codigo;
  final String rotulo;

  static CanalRegra de(String? codigo) => CanalRegra.values.firstWhere(
        (c) => c.codigo == codigo,
        orElse: () => CanalRegra.push,
      );
}

/// Converte o texto digitado em reais ("1.234,56", "1234,5", "1234.56") em número.
/// Retorna `null` se não for um número válido ou não for maior que zero.
double? parseValorBr(String texto) {
  var t = texto.trim().replaceAll(RegExp(r'\s'), '').replaceAll('R\$', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    // Vírgula é o separador decimal; pontos são milhares.
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  final v = double.tryParse(t);
  if (v == null || !v.isFinite || v <= 0) return null;
  return (v * 100).round() / 100;
}

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Frase que descreve a regra, ex.: "Gasto em Lazer acima de R$ 200,00".
String descreverRegra(Map<String, dynamic> regra) {
  final limite = num.tryParse('${regra['valorLimite']}');
  final valor = limite == null ? '—' : _brl.format(limite);
  switch (TipoRegra.de(regra['tipoEvento'] as String?)) {
    case TipoRegra.saldoMinimo:
      final conta = regra['conta'] as Map?;
      final sufixo = conta == null ? '' : ' (conta ${conta['numeroMascarado'] ?? conta['id']})';
      return 'Saldo abaixo de $valor$sufixo';
    case TipoRegra.transacaoGrande:
      return 'Transação acima de $valor';
    case TipoRegra.despesaCategoria:
      final cat = (regra['categoria'] as Map?)?['nome'] ?? 'categoria';
      return 'Gasto em $cat acima de $valor';
    case TipoRegra.pixRecebido:
      return limite == null ? 'Qualquer Pix recebido' : 'Pix recebido a partir de $valor';
    case TipoRegra.pixEnviado:
      return limite == null ? 'Qualquer Pix enviado' : 'Pix enviado a partir de $valor';
  }
}
