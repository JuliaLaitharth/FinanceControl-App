import { createHash } from 'crypto';
import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { JwtService } from '@nestjs/jwt';
import { HttpException, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createPrismaMock } from '../test-utils/prisma.mock';
import { OauthService } from './oauth.service';

const usuarioFake = (overrides = {}) => ({
  id: 1,
  email: 'user@test.com',
  senhaHash: bcrypt.hashSync('senha123', 10),
  nome: 'Usuário Teste',
  ...overrides,
});

const codigoFake = (overrides = {}) => ({
  id: 10,
  codigo: 'abc123',
  usuarioId: 1,
  redirectUri: 'https://amazon.com/callback',
  expiraEm: new Date(Date.now() + 300_000),
  usado: false,
  ...overrides,
});

const vinculoFake = (overrides = {}) => ({
  id: 5,
  usuarioId: 1,
  alexaUserId: null,
  accessToken: 'jwt-old',
  refreshToken: 'refresh-token-valid',
  expiraEm: new Date(Date.now() + 86_400_000),
  ativo: true,
  ...overrides,
});

describe('OauthService', () => {
  let service: OauthService;
  let prisma: ReturnType<typeof createPrismaMock>;
  let jwt: jest.Mocked<JwtService>;

  beforeEach(() => {
    prisma = createPrismaMock();
    jwt = {
      signAsync: jest.fn().mockResolvedValue('jwt-access-token') as jest.MockedFunction<JwtService['signAsync']>,
    } as unknown as jest.Mocked<JwtService>;
    service = new OauthService(prisma as never, jwt, {
      get: (k: string) =>
        ({
          ALEXA_OAUTH_CLIENT_ID: 'skill-id',
          ALEXA_OAUTH_CLIENT_SECRET: 'skill-secret',
          ALEXA_REDIRECT_URIS: 'https://pitangui.amazon.com/cb, https://layla.amazon.com/cb',
        })[k],
    } as never);
  });

  // ─── validarCredenciais ──────────────────────────────────────────────────

  describe('validarCredenciais()', () => {
    it('retorna usuário com credenciais válidas', async () => {
      prisma.usuario.findUnique.mockResolvedValue(usuarioFake() as never);
      const result = await service.validarCredenciais('user@test.com', 'senha123');
      expect(result.id).toBe(1);
    });

    it('lança UnauthorizedException com senha errada e conta a tentativa', async () => {
      prisma.usuario.findUnique.mockResolvedValue(usuarioFake() as never);
      prisma.usuario.update.mockResolvedValue({ tentativasFalhas: 1 } as never);

      await expect(service.validarCredenciais('user@test.com', 'errada')).rejects.toThrow(
        UnauthorizedException,
      );
      expect(prisma.usuario.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { tentativasFalhas: { increment: 1 } } }),
      );
    });

    it('bloqueia por 15 minutos na 5ª falha', async () => {
      prisma.usuario.findUnique.mockResolvedValue(usuarioFake() as never);
      prisma.usuario.update.mockResolvedValue({ tentativasFalhas: 5 } as never);

      await expect(service.validarCredenciais('user@test.com', 'errada')).rejects.toThrow(
        UnauthorizedException,
      );

      expect(prisma.usuario.update).toHaveBeenLastCalledWith(
        expect.objectContaining({
          data: { tentativasFalhas: 0, bloqueadoAte: expect.any(Date) },
        }),
      );
    });

    it('recusa (429) conta bloqueada, mesmo com a senha certa', async () => {
      prisma.usuario.findUnique.mockResolvedValue(
        usuarioFake({ bloqueadoAte: new Date(Date.now() + 10 * 60_000) }) as never,
      );

      await expect(service.validarCredenciais('user@test.com', 'senha123')).rejects.toThrow(
        HttpException,
      );
      expect(prisma.usuario.update).not.toHaveBeenCalled();
    });

    it('zera as falhas anteriores depois de um login correto', async () => {
      prisma.usuario.findUnique.mockResolvedValue(usuarioFake({ tentativasFalhas: 3 }) as never);
      prisma.usuario.update.mockResolvedValue({} as never);

      await service.validarCredenciais('user@test.com', 'senha123');

      expect(prisma.usuario.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { tentativasFalhas: 0, bloqueadoAte: null } }),
      );
    });

    it('lança UnauthorizedException quando usuário não existe', async () => {
      prisma.usuario.findUnique.mockResolvedValue(null);
      await expect(service.validarCredenciais('nobody@test.com', 'any')).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });

  // ─── gerarCodigo ─────────────────────────────────────────────────────────

  describe('gerarCodigo()', () => {
    it('cria registro e retorna string de 64 chars hex', async () => {
      prisma.codigoOAuth.create.mockResolvedValue(codigoFake() as never);
      const code = await service.gerarCodigo(1, 'https://amazon.com/callback');
      expect(code).toHaveLength(64);
      expect(prisma.codigoOAuth.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ usuarioId: 1 }),
        }),
      );
    });
  });

  // ─── trocarCodigo ────────────────────────────────────────────────────────

  describe('trocarCodigo()', () => {
    it('troca código válido por tokens OAuth', async () => {
      prisma.codigoOAuth.findUnique.mockResolvedValue(codigoFake() as never);
      prisma.codigoOAuth.update.mockResolvedValue(codigoFake({ usado: true }) as never);
      prisma.vinculoAlexa.create.mockResolvedValue(vinculoFake() as never);

      const result = await service.trocarCodigo('abc123', 'https://amazon.com/callback');

      expect(result.access_token).toBe('jwt-access-token');
      expect(result.token_type).toBe('Bearer');
      expect(typeof result.refresh_token).toBe('string');
      expect(prisma.codigoOAuth.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { usado: true } }),
      );
    });

    it('lança UnauthorizedException para código já usado', async () => {
      prisma.codigoOAuth.findUnique.mockResolvedValue(codigoFake({ usado: true }) as never);
      await expect(service.trocarCodigo('abc123', 'https://amazon.com/callback')).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('lança UnauthorizedException para código expirado', async () => {
      prisma.codigoOAuth.findUnique.mockResolvedValue(
        codigoFake({ expiraEm: new Date(Date.now() - 1000) }) as never,
      );
      await expect(service.trocarCodigo('abc123', 'https://amazon.com/callback')).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('lança UnauthorizedException quando redirect_uri não corresponde', async () => {
      prisma.codigoOAuth.findUnique.mockResolvedValue(codigoFake() as never);
      await expect(
        service.trocarCodigo('abc123', 'https://outro.com/callback'),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  // ─── refresharToken ──────────────────────────────────────────────────────

  describe('refresharToken()', () => {
    it('renova access_token com refresh_token válido', async () => {
      prisma.vinculoAlexa.findFirst.mockResolvedValue(vinculoFake() as never);
      prisma.vinculoAlexa.update.mockResolvedValue(vinculoFake() as never);

      const result = await service.refresharToken('refresh-token-valid');

      expect(result.access_token).toBe('jwt-access-token');
      expect(result.token_type).toBe('Bearer');
    });

    it('busca e grava os tokens apenas como hash', async () => {
      prisma.vinculoAlexa.findFirst.mockResolvedValue(vinculoFake() as never);
      prisma.vinculoAlexa.update.mockResolvedValue(vinculoFake() as never);

      await service.refresharToken('refresh-token-valid');

      const hash = (v: string) => createHash('sha256').update(v).digest('hex');
      expect(prisma.vinculoAlexa.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ refreshToken: hash('refresh-token-valid') }),
        }),
      );
      expect(prisma.vinculoAlexa.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ accessToken: hash('jwt-access-token') }) }),
      );
    });

    it('lança UnauthorizedException para refresh_token inválido', async () => {
      prisma.vinculoAlexa.findFirst.mockResolvedValue(null);
      await expect(service.refresharToken('invalid')).rejects.toThrow(UnauthorizedException);
    });
  });
});
