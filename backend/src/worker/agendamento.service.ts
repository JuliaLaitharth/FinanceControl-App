import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import { JOB_AGENDAR, PLUGGY_SYNC_QUEUE, PluggySyncJobData } from './worker.processor.js';

export const AGENDADOR_ID = 'sync-agendado';
const PADRAO_MINUTOS = 15; // RNF05: alertas em até 15 minutos

/** Lê SYNC_INTERVALO_MINUTOS: vazio ou inválido = 15; 0 desliga; mínimo 1. */
export function lerIntervaloMinutos(valor: string | undefined): number {
  if (valor === undefined || valor.trim() === '') return PADRAO_MINUTOS;
  const n = Number(valor);
  if (!Number.isFinite(n) || n < 0) return PADRAO_MINUTOS;
  return n === 0 ? 0 : Math.max(1, Math.floor(n));
}

/**
 * Cria (ou atualiza) o agendamento que sincroniza periodicamente todas as contas conectadas,
 * para os alertas chegarem sem o usuário abrir o app. O agendamento fica no Redis, então
 * reiniciar a API não o duplica.
 */
@Injectable()
export class AgendamentoService implements OnApplicationBootstrap {
  private readonly logger = new Logger(AgendamentoService.name);

  constructor(
    @InjectQueue(PLUGGY_SYNC_QUEUE) private readonly fila: Queue<PluggySyncJobData>,
    private readonly config: ConfigService,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    const minutos = lerIntervaloMinutos(this.config.get<string>('SYNC_INTERVALO_MINUTOS'));
    try {
      if (minutos === 0) {
        await this.fila.removeJobScheduler(AGENDADOR_ID);
        this.logger.log('Sincronização agendada desligada.');
        return;
      }
      await this.fila.upsertJobScheduler(
        AGENDADOR_ID,
        { every: minutos * 60_000 },
        { name: JOB_AGENDAR, opts: { removeOnComplete: 20, removeOnFail: 20 } },
      );
      this.logger.log(`Sincronização agendada a cada ${minutos} min.`);
    } catch (erro) {
      // Sem o agendamento a API continua útil (webhook e sincronização manual).
      this.logger.error(`Não foi possível agendar a sincronização: ${(erro as Error).message}`);
    }
  }
}
