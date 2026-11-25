import { describe, expect, it } from '@jest/globals';
import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

const ctx = (method: string, originalUrl: string) =>
  ({
    switchToHttp: () => ({ getRequest: () => ({ method, originalUrl }) }),
  }) as unknown as ExecutionContext;

describe('JwtAuthGuard — escopo Alexa', () => {
  const guard = new JwtAuthGuard();
  const alexa = { sub: 1, userId: 1, scope: 'alexa' };

  it('permite saldo e resumo de gastos', () => {
    expect(guard.handleRequest(null, alexa, null, ctx('GET', '/contas/saldo'))).toBe(alexa);
    expect(
      guard.handleRequest(null, alexa, null, ctx('GET', '/transacoes/resumo-categorias?dataInicio=2026-11-01')),
    ).toBe(alexa);
  });

  it('permite só a leitura dos alertas, sem marcar como lido', () => {
    expect(guard.handleRequest(null, alexa, null, ctx('GET', '/notificacoes?naoLidas=true'))).toBe(alexa);
    expect(() => guard.handleRequest(null, alexa, null, ctx('PATCH', '/notificacoes/ler-todas'))).toThrow(ForbiddenException);
    expect(() => guard.handleRequest(null, alexa, null, ctx('GET', '/notificacoes/contagem'))).toThrow(ForbiddenException);
  });

  it('bloqueia qualquer outra rota', () => {
    expect(() => guard.handleRequest(null, alexa, null, ctx('GET', '/transacoes'))).toThrow(ForbiddenException);
    expect(() => guard.handleRequest(null, alexa, null, ctx('DELETE', '/auth/conta'))).toThrow(ForbiddenException);
  });

  it('não restringe tokens de sessão normais', () => {
    const normal = { sub: 1, userId: 1, sessaoId: 'x' };
    expect(guard.handleRequest(null, normal, null, ctx('DELETE', '/consentimentos/1'))).toBe(normal);
  });
});
