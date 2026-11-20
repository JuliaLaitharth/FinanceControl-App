import { InjectQueue } from '@nestjs/bullmq';
import {
  Body,
  Controller,
  Headers,
  HttpCode,
  Logger,
  Post,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import { createHash, timingSafeEqual } from 'crypto';
import { PLUGGY_SYNC_QUEUE } from '../worker/worker.processor.js';
import { PrismaService } from '../prisma/prisma.service.js';

interface PluggyWebhookPayload {
  event: string;
  item?: { id: string };
  itemId?: string;
  [key: string]: unknown;
}

@Controller('webhooks')
export class WebhookController {
  private readonly logger = new Logger(WebhookController.name);
  private readonly secret: string;

  constructor(
    config: ConfigService,
    @InjectQueue(PLUGGY_SYNC_QUEUE) private readonly syncQueue: Queue,
    private readonly prisma: PrismaService,
  ) {
    this.secret = config.getOrThrow<string>('PLUGGY_WEBHOOK_SECRET');
  }

  @Post('pluggy')
  @HttpCode(200)
  async handlePluggy(
    @Body() payload: PluggyWebhookPayload,
    @Headers('x-webhook-secret') secretHeader: string,
  ) {
    this.validarSegredo(secretHeader);

    const rawItemId = payload.item?.id ?? payload.itemId;
    this.logger.log(
      `Webhook Pluggy: evento=${payload.event} itemId=${rawItemId ?? 'n/a'}`,
    );

    // Encontra o usuário via SHA-256 do itemId
    if (rawItemId) {
      const itemIdHash = createHash('sha256').update(rawItemId).digest('hex');
      const consentimento = await this.prisma.consentimento.findFirst({
        where: { itemIdHash },
        select: { usuarioId: true },
      });

      if (consentimento) {
        await this.syncQueue.add(
          'sync',
          { usuarioId: consentimento.usuarioId, event: payload.event },
          {
            attempts: 3,
            backoff: { type: 'exponential', delay: 5_000 },
            removeOnComplete: 100,
            removeOnFail: 50,
          },
        );
        this.logger.log(
          `Job enfileirado para usuário ${consentimento.usuarioId}`,
        );
      } else {
        this.logger.warn(
          `Nenhum consentimento encontrado para itemIdHash — evento ignorado`,
        );
      }
    }

    return { received: true };
  }

  /**
   * O Pluggy não assina webhooks de item com HMAC: a autenticação é um header
   * customizado, definido por nós ao cadastrar o webhook (POST /webhooks, campo
   * `headers`). Aqui comparamos esse header com PLUGGY_WEBHOOK_SECRET.
   */
  private validarSegredo(recebido: string | undefined) {
    if (!recebido) throw new UnauthorizedException('Segredo do webhook ausente');
    const a = createHash('sha256').update(recebido).digest();
    const b = createHash('sha256').update(this.secret).digest();
    if (!timingSafeEqual(a, b)) {
      throw new UnauthorizedException('Segredo do webhook inválido');
    }
  }
}
