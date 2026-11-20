import { HttpException, HttpStatus, Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service.js';
import {
  AlexaOauthConfig,
  clienteIdConfere,
  clienteValido,
  lerConfigOauth,
  redirectUriPermitido,
} from './alexa-oauth.config.js';

const ALEXA_TOKEN_DIAS = 30;
const CODIGO_MINUTOS = 5;
// Mesmas regras do login do app (HU01): 5 falhas → bloqueio de 15 minutos.
const MAX_TENTATIVAS = 5;
const BLOQUEIO_MINUTOS = 15;

const emMinutos = (min: number) => new Date(Date.now() + min * 60_000);
const emDias = (dias: number) => new Date(Date.now() + dias * 86_400_000);

@Injectable()
export class OauthService {
  private readonly logger = new Logger('OAuth');
  private readonly cfg: AlexaOauthConfig;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    config: ConfigService,
  ) {
    this.cfg = lerConfigOauth((k) => config.get<string>(k));
  }

  /** O endereço de retorno está na lista configurada (ALEXA_REDIRECT_URIS)? */
  redirectUriPermitido(uri: string | undefined): boolean {
    return redirectUriPermitido(uri, this.cfg.redirectUris);
  }

  /** O client_id recebido em /oauth/authorize é o da skill? */
  clienteIdConfere(clientId: string | undefined): boolean {
    return clienteIdConfere(this.cfg, clientId);
  }

  /** Credenciais do cliente (skill) em /oauth/token. */
  clienteValido(clientId: string | undefined, clientSecret: string | undefined): boolean {
    return clienteValido(this.cfg, clientId, clientSecret);
  }

  async validarCredenciais(email: string, senha: string) {
    const usuario = await this.prisma.usuario.findUnique({ where: { email } });
    if (!usuario) throw new UnauthorizedException('E-mail ou senha incorretos');

    // Sem isto, esta tela permitiria tentar senhas sem limite (o /auth/login bloqueia).
    if (usuario.bloqueadoAte && usuario.bloqueadoAte > new Date()) {
      const minutos = Math.ceil((usuario.bloqueadoAte.getTime() - Date.now()) / 60_000);
      throw new HttpException(
        `Muitas tentativas inválidas. Tente novamente em ${minutos} minuto(s).`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const ok = await bcrypt.compare(senha, usuario.senhaHash);
    if (!ok) {
      const atualizado = await this.prisma.usuario.update({
        where: { id: usuario.id },
        data: { tentativasFalhas: { increment: 1 } },
      });
      if (atualizado.tentativasFalhas >= MAX_TENTATIVAS) {
        await this.prisma.usuario.update({
          where: { id: usuario.id },
          data: { tentativasFalhas: 0, bloqueadoAte: emMinutos(BLOQUEIO_MINUTOS) },
        });
      }
      throw new UnauthorizedException('E-mail ou senha incorretos');
    }

    if (usuario.tentativasFalhas > 0) {
      await this.prisma.usuario.update({
        where: { id: usuario.id },
        data: { tentativasFalhas: 0, bloqueadoAte: null },
      });
    }
    return usuario;
  }

  async gerarCodigo(usuarioId: number, redirectUri: string): Promise<string> {
    const codigo = randomBytes(32).toString('hex');
    await this.prisma.codigoOAuth.create({
      data: { codigo, usuarioId, redirectUri, expiraEm: emMinutos(CODIGO_MINUTOS) },
    });
    return codigo;
  }

  async trocarCodigo(code: string, redirectUri: string) {
    const registro = await this.prisma.codigoOAuth.findUnique({ where: { codigo: code } });
    if (!registro || registro.usado || registro.expiraEm < new Date()) {
      this.logger.warn(
        `troca de código recusada: ${!registro ? 'código não encontrado' : registro.usado ? 'código já usado' : 'código expirado'}`,
      );
      throw new UnauthorizedException('Código inválido ou expirado');
    }
    if (registro.redirectUri !== redirectUri) {
      this.logger.warn(`troca de código recusada: redirect_uri diferente (esperado ${registro.redirectUri}, recebido ${redirectUri})`);
      throw new UnauthorizedException('redirect_uri não corresponde');
    }

    await this.prisma.codigoOAuth.update({ where: { id: registro.id }, data: { usado: true } });

    const accessToken = await this.jwt.signAsync(
      { sub: registro.usuarioId, scope: 'alexa' },
      { expiresIn: `${ALEXA_TOKEN_DIAS}d` },
    );
    const refreshToken = randomBytes(48).toString('hex');
    const expiraEm = emDias(ALEXA_TOKEN_DIAS);

    await this.prisma.vinculoAlexa.create({
      data: {
        usuarioId: registro.usuarioId,
        accessToken,
        refreshToken,
        expiraEm,
      },
    });

    return {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: ALEXA_TOKEN_DIAS * 86400,
      refresh_token: refreshToken,
    };
  }

  async refresharToken(refreshToken: string) {
    const vinculo = await this.prisma.vinculoAlexa.findFirst({
      where: { refreshToken, ativo: true, expiraEm: { gt: new Date() } },
    });
    if (!vinculo) throw new UnauthorizedException('refresh_token inválido');

    const accessToken = await this.jwt.signAsync(
      { sub: vinculo.usuarioId, scope: 'alexa' },
      { expiresIn: `${ALEXA_TOKEN_DIAS}d` },
    );
    const expiraEm = emDias(ALEXA_TOKEN_DIAS);

    await this.prisma.vinculoAlexa.update({
      where: { id: vinculo.id },
      data: { accessToken, expiraEm },
    });

    return {
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: ALEXA_TOKEN_DIAS * 86400,
    };
  }
}
