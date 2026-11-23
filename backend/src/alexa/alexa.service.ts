import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service.js';

/**
 * Enquanto a skill está em desenvolvimento (não publicada), a Amazon só aceita
 * eventos em /stages/development; o endereço de produção responde com erro.
 * Defina ALEXA_SKILL_STAGE=live depois de publicar a skill.
 */
export const urlProactiveEvents = (stage: string | undefined): string =>
  stage === 'live'
    ? 'https://api.amazonalexa.com/v1/proactiveEvents'
    : 'https://api.amazonalexa.com/v1/proactiveEvents/stages/development';

@Injectable()
export class AlexaService {
  private readonly logger = new Logger(AlexaService.name);
  private readonly clientId: string | undefined;
  private readonly clientSecret: string | undefined;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {
    this.clientId = this.config.get('ALEXA_CLIENT_ID');
    this.clientSecret = this.config.get('ALEXA_CLIENT_SECRET');
  }

  async enviarAlertaTransacao(usuarioId: number, mensagem: string): Promise<void> {
    if (!this.clientId || !this.clientSecret) {
      this.logger.warn('Alexa: ALEXA_CLIENT_ID/ALEXA_CLIENT_SECRET não configurados; aviso por voz não enviado.');
      return;
    }

    const vinculo = await this.prisma.vinculoAlexa.findFirst({
      where: { usuarioId, ativo: true, NOT: { alexaUserId: null } },
    });
    if (!vinculo?.alexaUserId) {
      this.logger.warn(
        `Alexa: usuário ${usuarioId} sem vínculo ativo ou sem ID da Alexa (diga "Alexa, abrir controle financeiro" uma vez); aviso não enviado.`,
      );
      return;
    }

    const lwaToken = await this.obterLwaToken();
    if (!lwaToken) return;

    await this.enviarEvento(vinculo.alexaUserId, mensagem, lwaToken);
  }

  private async obterLwaToken(): Promise<string | null> {
    try {
      const { default: axios } = await import('axios');
      const params = new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: this.clientId!,
        client_secret: this.clientSecret!,
        scope: 'alexa::proactive_events',
      });
      const { data } = await axios.post<{ access_token: string }>(
        'https://api.amazon.com/auth/o2/token',
        params.toString(),
        { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
      );
      return data.access_token;
    } catch (err) {
      this.logger.warn(`Falha ao obter token LWA para Proactive Events: ${detalheErro(err)}`);
      return null;
    }
  }

  private async enviarEvento(
    alexaUserId: string,
    mensagem: string,
    lwaToken: string,
  ): Promise<void> {
    try {
      const { default: axios } = await import('axios');
      const evento = {
        timestamp: new Date().toISOString(),
        referenceId: `fc-${Date.now()}`,
        payload: {
          type: 'AMAZON.MessageAlert.Activated',
          version: '1.0',
          data: {
            state: { status: 'UNREAD', freshness: 'NEW' },
            messageGroup: {
              creator: { name: 'FinanceControl' },
              count: 1,
              urgency: 'URGENT',
            },
          },
        },
        relevantAudience: { type: 'Unicast', payload: { user: alexaUserId } },
        expiryTime: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      };

      await axios.post(
        urlProactiveEvents(this.config.get<string>('ALEXA_SKILL_STAGE')),
        evento,
        { headers: { Authorization: `Bearer ${lwaToken}` } },
      );
      this.logger.log(`Proactive Event enviado para Alexa user: ${alexaUserId}`);
    } catch (err) {
      this.logger.warn(`Falha ao enviar Proactive Event: ${detalheErro(err)}`);
    }
  }
}

/** Resumo curto do erro do axios (status e corpo), sem cabeçalhos nem credenciais. */
function detalheErro(err: unknown): string {
  const e = err as { response?: { status?: number; data?: unknown }; message?: string };
  if (e?.response) return `HTTP ${e.response.status} ${JSON.stringify(e.response.data)}`;
  return e?.message ?? String(err);
}
