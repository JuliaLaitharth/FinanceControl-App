import { describe, expect, it } from '@jest/globals';
import { ehPix, enviaAlexa, enviaPush } from './worker.processor';

describe('canal da regra de alerta', () => {
  it.each([
    ['PUSH', true, false],
    ['ALEXA', false, true],
    ['AMBOS', true, true],
    ['EMAIL', false, false], // legado: nunca enviou e-mail
  ])('%s → push=%s alexa=%s', (canal, push, alexa) => {
    expect(enviaPush(canal)).toBe(push);
    expect(enviaAlexa(canal)).toBe(alexa);
  });
});

describe('detecção de Pix', () => {
  it.each([
    [{ metodoPagamento: 'PIX', descricao: 'Transferência' }, true],
    [{ metodoPagamento: null, descricao: 'PIX RECEBIDO JOAO' }, true],
    [{ metodoPagamento: 'TED', descricao: 'Pagamento de boleto' }, false],
    [{ metodoPagamento: null, descricao: 'Pixel Store' }, false],
  ])('%j → %s', (tx, esperado) => {
    expect(ehPix(tx)).toBe(esperado);
  });
});
