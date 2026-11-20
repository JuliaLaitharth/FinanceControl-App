/// Períodos oferecidos no relatório de despesas por categoria.
enum PeriodoRelatorio {
  mesAtual('Este mês', 'mês atual'),
  mesAnterior('Mês anterior', 'mês anterior'),
  tresMeses('3 meses', 'últimos 3 meses');

  const PeriodoRelatorio(this.rotulo, this.descricao);

  /// Texto do seletor.
  final String rotulo;

  /// Texto usado em frases ("Nenhuma despesa no ...").
  final String descricao;

  /// Intervalo [inicio, fim) no formato AAAA-MM-DD. `fim` nulo significa "até hoje".
  /// `DateTime` normaliza meses fora de 1..12 (mês 0 vira dezembro do ano anterior).
  ({String inicio, String? fim}) intervalo(DateTime hoje) {
    switch (this) {
      case PeriodoRelatorio.mesAtual:
        return (inicio: _fmt(DateTime(hoje.year, hoje.month, 1)), fim: null);
      case PeriodoRelatorio.mesAnterior:
        return (
          inicio: _fmt(DateTime(hoje.year, hoje.month - 1, 1)),
          fim: _fmt(DateTime(hoje.year, hoje.month, 1)),
        );
      case PeriodoRelatorio.tresMeses:
        return (inicio: _fmt(DateTime(hoje.year, hoje.month - 2, 1)), fim: null);
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
