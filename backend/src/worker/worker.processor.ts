import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { AlexaService } from '../alexa/alexa.service.js';
import { AuditService } from '../audit/audit.service.js';
import { FcmService } from '../fcm/fcm.service.js';
import { NotificacaoService } from '../notificacao/notificacao.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { TransacaoService } from '../transacao/transacao.service.js';

export interface PluggySyncJobData {
  usuarioId: number;
  event: string;
}

export const PLUGGY_SYNC_QUEUE = 'pluggy-sync';
/** Job periódico que enfileira a sincronização de cada usuário com conta conectada. */
export const JOB_AGENDAR = 'agendar';

/** Canal da regra: PUSH (app), ALEXA (alerta proativo) ou AMBOS. */
export const enviaPush = (canal: string): boolean => canal === 'PUSH' || canal === 'AMBOS';
export const enviaAlexa = (canal: string): boolean => canal === 'ALEXA' || canal === 'AMBOS';

@Processor(PLUGGY_SYNC_QUEUE, {
  // Reprocessamento automático: 3 tentativas com backoff exponencial
  concurrency: 2,
})
export class SyncWorkerProcessor extends WorkerHost {
  private readonly logger = new Logger(SyncWorkerProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly transacaoService: TransacaoService,
    private readonly notificacaoService: NotificacaoService,
    private readonly fcmService: FcmService,
    private readonly alexaService: AlexaService,
    private readonly audit: AuditService,
    @InjectQueue(PLUGGY_SYNC_QUEUE) private readonly fila: Queue<PluggySyncJobData>,
  ) {
    super();
  }

  /** Um job por usuário; a deduplicação evita acumular se a anterior ainda estiver na fila. */
  private async agendarUsuarios(): Promise<void> {
    const usuarios = await this.prisma.consentimento.findMany({
      where: { status: 'ATIVO' },
      select: { usuarioId: true },
      distinct: ['usuarioId'],
    });
    for (const { usuarioId } of usuarios) {
      await this.fila.add(
        'sync',
        { usuarioId, event: 'agendado' },
        {
          deduplication: { id: `agendado-${usuarioId}` },
          attempts: 3,
          backoff: { type: 'exponential', delay: 5_000 },
          removeOnComplete: 100,
          removeOnFail: 50,
        },
      );
    }
    this.logger.log(`Sincronização agendada: ${usuarios.length} usuário(s) enfileirado(s).`);
  }

  async process(job: Job<PluggySyncJobData>): Promise<void> {
    if (job.name === JOB_AGENDAR) return this.agendarUsuarios();

    const { usuarioId, event } = job.data;
    this.logger.log(`Processando job ${job.id} — evento: ${event}, usuário: ${usuarioId}`);

    // 1. Sincroniza transações via Pluggy
    const { sincronizadas, novasIds } = await this.transacaoService.sincronizar(usuarioId);
    this.logger.log(`Sincronizadas ${sincronizadas} transações (${novasIds.length} novas)`);

    // 2. Avalia apenas as transações NOVAS desta sincronização (a data da transação vem do banco
    //    e normalmente é anterior ao momento do sync, então não serve como filtro de recência).
    const txsRecentes = novasIds.length
      ? await this.prisma.transacao.findMany({
          where: { id: { in: novasIds }, conta: { consentimento: { usuarioId, status: 'ATIVO' } } },
          include: { conta: true },
        })
      : [];

    // 3. Busca contas para verificar saldo mínimo
    const contas = await this.prisma.contaBancaria.findMany({
      where: { consentimento: { usuarioId, status: 'ATIVO' } },
    });

    // 4. Busca regras ativas do usuário
    const regras = await this.prisma.regraAlerta.findMany({
      where: { usuarioId, ativa: true },
    });

    // 5. Busca FCM token do usuário
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: usuarioId },
      select: { fcmToken: true, nome: true },
    });

    for (const regra of regras) {
      if (regra.tipoEvento === 'SALDO_MINIMO') {
        // Regra nova: só a conta escolhida. Regra antiga (sem conta): todas as contas.
        const alvo = regra.contaId ? contas.filter((c) => c.id === regra.contaId) : contas;
        await this.avaliarSaldoMinimo(usuarioId, regra, alvo, usuario?.fcmToken ?? null);
        continue;
      }

      for (const tx of txsRecentes) {
        if (await this.regraCorresponde(regra, tx)) {
          const notif = await this.notificacaoService.criarIdempotente({
            regraId: regra.id,
            transacaoId: tx.id,
            mensagem: this.gerarMensagem(regra, tx),
            canal: regra.canal,
          });

          if (notif && usuario?.fcmToken && enviaPush(regra.canal)) {
            const enviado = await this.fcmService.enviar(
              usuario.fcmToken,
              'Alerta Financeiro',
              notif.mensagem,
            );
            await this.notificacaoService.atualizarStatus(
              notif.id,
              enviado ? 'ENVIADO' : 'FALHA',
              new Date(),
            );
            await this.audit.registrar(usuarioId, enviado ? 'NOTIFICACAO_PUSH_ENVIADA' : 'NOTIFICACAO_PUSH_FALHA', 'notificacao');
          }

          if (notif && enviaAlexa(regra.canal)) {
            await this.alexaService.enviarAlertaTransacao(usuarioId, notif.mensagem);
            await this.audit.registrar(usuarioId, 'NOTIFICACAO_ALEXA_SOLICITADA', 'notificacao');
          }
          if (notif) await this.audit.registrar(usuarioId, 'NOTIFICACAO_GERADA', 'notificacao');
        }
      }
    }
  }

  private async regraCorresponde(
    regra: { tipoEvento: string; valorLimite: unknown; categoriaId: number | null },
    tx: {
      tipo: string;
      valor: unknown;
      categoriaId: number | null;
      descricao?: string;
      metodoPagamento?: string | null;
    },
  ): Promise<boolean> {
    const limite = Number(regra.valorLimite ?? 0);
    const valor = Number(tx.valor ?? 0);

    switch (regra.tipoEvento) {
      case 'TRANSACAO_GRANDE':
        return tx.tipo === 'DEBIT' && valor > limite;
      case 'DESPESA_CATEGORIA':
        return tx.tipo === 'DEBIT' && tx.categoriaId === regra.categoriaId && valor > limite;
      case 'PIX_RECEBIDO':
        return ehPix(tx) && tx.tipo === 'CREDIT' && valor >= limite;
      case 'PIX_ENVIADO':
        return ehPix(tx) && tx.tipo === 'DEBIT' && valor >= limite;
      default:
        return false;
    }
  }

  private async avaliarSaldoMinimo(
    usuarioId: number,
    regra: { id: number; valorLimite: unknown; canal: string },
    contas: Array<{ id: number; saldoAtual: unknown; tipo: string }>,
    fcmToken: string | null,
  ) {
    const limite = Number(regra.valorLimite ?? 0);
    // Cartão de crédito tem saldo negativo (fatura em aberto): não é "saldo mínimo".
    for (const conta of contas.filter((c) => c.tipo !== 'CREDIT')) {
      if (Number(conta.saldoAtual) < limite) {
        // Idempotência para saldo mínimo: verifica se já notificou nas últimas 24h
        const jaNot = await this.prisma.notificacao.findFirst({
          where: {
            regraId: regra.id,
            transacaoId: null,
            dataEnvio: { gte: new Date(Date.now() - 24 * 3_600_000) },
          },
        });
        if (jaNot) continue;

        const mensagem = `Saldo abaixo do limite: R$ ${Number(conta.saldoAtual).toFixed(2)} (mínimo: R$ ${limite.toFixed(2)})`;
        const notif = await this.notificacaoService.criarIdempotente({
          regraId: regra.id,
          transacaoId: null,
          mensagem,
          canal: regra.canal,
        });

        if (notif && fcmToken && enviaPush(regra.canal)) {
          const enviado = await this.fcmService.enviar(fcmToken, 'Saldo baixo', mensagem);
          await this.notificacaoService.atualizarStatus(notif.id, enviado ? 'ENVIADO' : 'FALHA', new Date());
          await this.audit.registrar(usuarioId, enviado ? 'NOTIFICACAO_PUSH_ENVIADA' : 'NOTIFICACAO_PUSH_FALHA', 'notificacao');
        }
        if (notif && enviaAlexa(regra.canal)) {
          await this.alexaService.enviarAlertaTransacao(usuarioId, mensagem);
          await this.audit.registrar(usuarioId, 'NOTIFICACAO_ALEXA_SOLICITADA', 'notificacao');
        }
        if (notif) await this.audit.registrar(usuarioId, 'NOTIFICACAO_GERADA', 'notificacao');
      }
    }
  }

  private gerarMensagem(
    regra: { tipoEvento: string; valorLimite: unknown },
    tx: { descricao: string; valor: unknown },
  ): string {
    const valor = Number(tx.valor).toFixed(2);
    switch (regra.tipoEvento) {
      case 'TRANSACAO_GRANDE':
        return `Transação de R$ ${valor}: "${tx.descricao}" acima do limite de R$ ${Number(regra.valorLimite).toFixed(2)}`;
      case 'DESPESA_CATEGORIA':
        return `Gasto de R$ ${valor} em "${tx.descricao}" acima do limite da categoria`;
      case 'PIX_RECEBIDO':
        return `Pix recebido: R$ ${valor} — "${tx.descricao}"`;
      case 'PIX_ENVIADO':
        return `Pix enviado: R$ ${valor} — "${tx.descricao}"`;
      default:
        return `Alerta: R$ ${valor} — "${tx.descricao}"`;
    }
  }
}

/** Pix: o Pluggy informa o método de pagamento; na falta dele, a descrição costuma citar "pix". */
export function ehPix(tx: { descricao?: string; metodoPagamento?: string | null }): boolean {
  return (tx.metodoPagamento ?? '').toUpperCase() === 'PIX' || /\bpix\b/i.test(tx.descricao ?? '');
}
