/** Quantos alertas a Alexa lê de uma vez (a fala longa cansa; o restante fica no app). */
export const MAXIMO_LIDOS = 3;

const escaparSsml = (t: string) => t.replace(/&/g, ' e ').replace(/[<>"]/g, ' ');

/** Troca "R$ 1234.50" por "1.234,50 reais", que a Alexa pronuncia corretamente. */
const valoresFalados = (t: string) =>
  t.replace(/R\$\s*(-?\d+(?:\.\d{1,2})?)/g, (_, n: string) => {
    const valor = new Intl.NumberFormat('pt-BR', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(Number(n));
    return `${valor} reais`;
  });

/** Monta a fala a partir das mensagens não lidas (da mais recente para a mais antiga). */
export function falaAlertas(mensagens: string[]): string {
  const unicas = [...new Set(mensagens.map((m) => m.trim()).filter(Boolean))];
  if (unicas.length === 0) return 'Você não tem alertas novos.';

  const lidas = unicas.slice(0, MAXIMO_LIDOS).map((m) => escaparSsml(valoresFalados(m)));
  const abertura =
    unicas.length === 1 ? 'Você tem um alerta novo.' : `Você tem ${unicas.length} alertas novos.`;
  const restante = unicas.length - lidas.length;
  const fim =
    restante === 0
      ? ''
      : restante === 1
        ? ' O outro está no aplicativo.'
        : ` Os outros ${restante} estão no aplicativo.`;
  return `${abertura} ${lidas.map((m) => `${m}.`).join(' ')}${fim}`;
}
