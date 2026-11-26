import { describe, expect, it, jest } from '@jest/globals';
import { createPrismaMock } from '../test-utils/prisma.mock';
import { AgendamentoService, lerIntervaloMinutos } from './agendamento.service';
import { SyncWorkerProcessor } from './worker.processor';

const fila = () => ({
  add: jest.fn().mockResolvedValue(undefined as never),
  upsertJobScheduler: jest.fn().mockResolvedValue(undefined as never),
  removeJobScheduler: jest.fn().mockResolvedValue(undefined as never),
});
const config = (v?: string) => ({ get: () => v });

describe('sincronização agendada', () => {
  it.each([
    [undefined, 15],
    ['', 15],
    ['abc', 15],
    ['-3', 15],
    ['0', 0],
    ['0.5', 1],
    ['5', 5],
  ])('intervalo %s → %s min', (valor, esperado) => {
    expect(lerIntervaloMinutos(valor)).toBe(esperado);
  });

  it('cria o agendamento com o intervalo configurado', async () => {
    const f = fila();
    await new AgendamentoService(f as never, config('1') as never).onApplicationBootstrap();
    expect(f.upsertJobScheduler).toHaveBeenCalledWith('sync-agendado', { every: 60_000 }, expect.anything());
  });

  it('com 0 remove o agendamento', async () => {
    const f = fila();
    await new AgendamentoService(f as never, config('0') as never).onApplicationBootstrap();
    expect(f.removeJobScheduler).toHaveBeenCalledWith('sync-agendado');
    expect(f.upsertJobScheduler).not.toHaveBeenCalled();
  });

  it('o job periódico enfileira uma sincronização por usuário, sem sincronizar na hora', async () => {
    const prisma = createPrismaMock();
    prisma.consentimento.findMany.mockResolvedValue([{ usuarioId: 1 }, { usuarioId: 2 }] as never);
    const transacoes = { sincronizar: jest.fn() };
    const f = fila();
    const worker = new SyncWorkerProcessor(
      prisma as never, transacoes as never, {} as never, {} as never, {} as never, {} as never, f as never,
    );

    await worker.process({ name: 'agendar', data: {} } as never);

    expect(f.add).toHaveBeenCalledTimes(2);
    expect(f.add).toHaveBeenCalledWith(
      'sync',
      { usuarioId: 2, event: 'agendado' },
      expect.objectContaining({ deduplication: { id: 'agendado-2' } }),
    );
    expect(transacoes.sincronizar).not.toHaveBeenCalled();
  });
});
