import { describe, expect, it } from '@jest/globals';
import { enviaAlexa, enviaPush } from './worker.processor';

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
