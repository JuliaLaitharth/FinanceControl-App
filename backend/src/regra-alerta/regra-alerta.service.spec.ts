import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { createPrismaMock } from '../test-utils/prisma.mock';
import { CreateRegraAlertaDto } from './dto/create-regra-alerta.dto';
import { UpdateRegraAlertaDto } from './dto/update-regra-alerta.dto';
import { RegraAlertaService } from './regra-alerta.service';

const regraFake = (overrides = {}) => ({
  id: 1,
  usuarioId: 42,
  tipoEvento: 'TRANSACAO_GRANDE',
  operador: 'MAIOR_QUE',
  valorLimite: 500,
  categoriaId: null,
  canal: 'PUSH',
  ativa: true,
  dataCriacao: new Date(),
  ...overrides,
});

describe('RegraAlertaService', () => {
  let service: RegraAlertaService;
  let prisma: ReturnType<typeof createPrismaMock>;
  let audit: jest.Mocked<AuditService>;

  beforeEach(() => {
    prisma = createPrismaMock();
    audit = {
      registrar: jest.fn().mockResolvedValue(undefined),
    } as unknown as jest.Mocked<AuditService>;
    service = new RegraAlertaService(prisma as never, audit);
  });

  // ─── criar ───────────────────────────────────────────────────────────────

  describe('criar()', () => {
    it('cria regra e registra auditoria', async () => {
      prisma.regraAlerta.create.mockResolvedValue(regraFake() as never);
      const dto: CreateRegraAlertaDto = {
        tipoEvento: 'TRANSACAO_GRANDE',
        operador: 'MAIOR_QUE',
        valorLimite: 500,
        canal: 'PUSH',
      };

      const result = await service.criar(dto, 42, '127.0.0.1');

      expect(prisma.regraAlerta.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ usuarioId: 42, tipoEvento: 'TRANSACAO_GRANDE' }),
        }),
      );
      expect(audit.registrar).toHaveBeenCalledWith(42, 'REGRA_CRIADA', 'regra_alerta', '127.0.0.1');
      expect(result.id).toBe(1);
    });

    it.each([
      ['sem valor limite', { tipoEvento: 'TRANSACAO_GRANDE', canal: 'PUSH' }],
      ['limite zero', { tipoEvento: 'SALDO_MINIMO', valorLimite: 0, canal: 'PUSH' }],
      ['despesa por categoria sem categoria', { tipoEvento: 'DESPESA_CATEGORIA', valorLimite: 100, canal: 'AMBOS' }],
    ])('rejeita regra %s', async (_nome, dto) => {
      await expect(service.criar(dto as CreateRegraAlertaDto, 42)).rejects.toThrow(BadRequestException);
      expect(prisma.regraAlerta.create).not.toHaveBeenCalled();
    });

    it('ignora a categoria em tipos que não a usam', async () => {
      prisma.regraAlerta.create.mockResolvedValue(regraFake() as never);

      await service.criar(
        { tipoEvento: 'TRANSACAO_GRANDE', valorLimite: 100, categoriaId: 7, canal: 'ALEXA' },
        42,
      );

      expect(prisma.regraAlerta.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ categoriaId: null }) }),
      );
    });
  });

  describe('criar() — saldo mínimo por conta e Pix', () => {
    it('cria saldo mínimo para uma conta do usuário', async () => {
      prisma.contaBancaria.findFirst.mockResolvedValue({ id: 5 } as never);
      prisma.regraAlerta.findFirst.mockResolvedValue(null as never);
      prisma.regraAlerta.create.mockResolvedValue(regraFake() as never);

      await service.criar({ tipoEvento: 'SALDO_MINIMO', valorLimite: 100, contaId: 5, canal: 'PUSH' }, 42);

      expect(prisma.regraAlerta.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ contaId: 5 }) }),
      );
    });

    it('exige a conta no saldo mínimo', async () => {
      await expect(
        service.criar({ tipoEvento: 'SALDO_MINIMO', valorLimite: 100, canal: 'PUSH' }, 42),
      ).rejects.toThrow(BadRequestException);
    });

    it('impede conta de outro usuário', async () => {
      prisma.contaBancaria.findFirst.mockResolvedValue(null as never);
      await expect(
        service.criar({ tipoEvento: 'SALDO_MINIMO', valorLimite: 100, contaId: 9, canal: 'PUSH' }, 42),
      ).rejects.toThrow(BadRequestException);
    });

    it('impede segundo alerta de saldo mínimo na mesma conta', async () => {
      prisma.contaBancaria.findFirst.mockResolvedValue({ id: 5 } as never);
      prisma.regraAlerta.findFirst.mockResolvedValue({ id: 3 } as never);
      await expect(
        service.criar({ tipoEvento: 'SALDO_MINIMO', valorLimite: 100, contaId: 5, canal: 'PUSH' }, 42),
      ).rejects.toThrow(ConflictException);
      expect(prisma.regraAlerta.create).not.toHaveBeenCalled();
    });

    it('aceita alerta de Pix sem valor limite', async () => {
      prisma.regraAlerta.create.mockResolvedValue(regraFake({ tipoEvento: 'PIX_RECEBIDO' }) as never);
      await service.criar({ tipoEvento: 'PIX_RECEBIDO', canal: 'PUSH' }, 42);
      expect(prisma.regraAlerta.create).toHaveBeenCalled();
    });
  });

  // ─── listar ──────────────────────────────────────────────────────────────

  describe('listar()', () => {
    it('retorna regras do usuário', async () => {
      prisma.regraAlerta.findMany.mockResolvedValue([regraFake()] as never);

      const result = await service.listar(42);

      expect(result).toHaveLength(1);
      expect(prisma.regraAlerta.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { usuarioId: 42 } }),
      );
    });
  });

  // ─── atualizar ───────────────────────────────────────────────────────────

  describe('atualizar()', () => {
    it('atualiza regra pertencente ao usuário', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(regraFake() as never);
      const updated = regraFake({ ativa: false });
      prisma.regraAlerta.update.mockResolvedValue(updated as never);
      const dto = { ativa: false } as UpdateRegraAlertaDto;

      const result = await service.atualizar(1, dto, 42);

      expect(prisma.regraAlerta.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 1 } }),
      );
      expect(result.ativa).toBe(false);
    });

    it('rejeita trocar para despesa por categoria sem informar a categoria', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(regraFake() as never);

      await expect(
        service.atualizar(1, { tipoEvento: 'DESPESA_CATEGORIA' } as UpdateRegraAlertaDto, 42),
      ).rejects.toThrow(BadRequestException);
      expect(prisma.regraAlerta.update).not.toHaveBeenCalled();
    });

    it('limpa a categoria ao trocar para um tipo que não a usa', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(
        regraFake({ tipoEvento: 'DESPESA_CATEGORIA', categoriaId: 3 }) as never,
      );
      prisma.regraAlerta.update.mockResolvedValue(regraFake() as never);

      await service.atualizar(1, { tipoEvento: 'TRANSACAO_GRANDE' } as UpdateRegraAlertaDto, 42);

      expect(prisma.regraAlerta.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ categoriaId: null }) }),
      );
    });

    it('lança ForbiddenException quando usuário não é dono', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(
        regraFake({ usuarioId: 99 }) as never,
      );

      await expect(
        service.atualizar(1, {} as UpdateRegraAlertaDto, 42),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ─── excluir ─────────────────────────────────────────────────────────────

  describe('excluir()', () => {
    it('exclui regra e registra auditoria', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(regraFake() as never);
      prisma.regraAlerta.delete.mockResolvedValue(regraFake() as never);

      await service.excluir(1, 42, '127.0.0.1');

      expect(prisma.regraAlerta.delete).toHaveBeenCalledWith({ where: { id: 1 } });
      expect(audit.registrar).toHaveBeenCalledWith(42, 'REGRA_EXCLUIDA', 'regra_alerta', '127.0.0.1');
    });

    it('lança NotFoundException quando regra não existe', async () => {
      prisma.regraAlerta.findUnique.mockResolvedValue(null);

      await expect(service.excluir(99, 42)).rejects.toThrow(NotFoundException);
      expect(prisma.regraAlerta.delete).not.toHaveBeenCalled();
    });
  });
});
