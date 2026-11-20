import { beforeEach, describe, expect, it } from '@jest/globals';
import { createPrismaMock } from '../test-utils/prisma.mock';
import { CATEGORIAS_PADRAO } from './categorias-padrao';
import { CategoriaService } from './categoria.service';

describe('CategoriaService.garantirCategoriasPadrao', () => {
  let prisma: ReturnType<typeof createPrismaMock>;
  let service: CategoriaService;

  beforeEach(() => {
    prisma = createPrismaMock();
    service = new CategoriaService(prisma as never);
  });

  it('banco vazio: cria todas as categorias padrão', async () => {
    prisma.categoria.findFirst.mockResolvedValue(null);
    prisma.categoria.create.mockResolvedValue({} as never);

    const criadas = await service.garantirCategoriasPadrao();

    expect(criadas).toBe(CATEGORIAS_PADRAO.length);
    expect(prisma.categoria.update).not.toHaveBeenCalled();
    expect(prisma.categoria.create).toHaveBeenCalledWith({
      data: { nome: 'Moradia', tipo: 'DESPESA', icone: '🏠', padraoSistema: true, usuarioId: null },
    });
  });

  it('é idempotente: se já existem, só atualiza e não duplica', async () => {
    prisma.categoria.findFirst.mockResolvedValue({ id: 7 } as never);
    prisma.categoria.update.mockResolvedValue({} as never);

    const criadas = await service.garantirCategoriasPadrao();

    expect(criadas).toBe(0);
    expect(prisma.categoria.create).not.toHaveBeenCalled();
    expect(prisma.categoria.update).toHaveBeenCalledTimes(CATEGORIAS_PADRAO.length);
  });

  it('cria só as que faltam', async () => {
    prisma.categoria.findFirst.mockImplementation((async (args: { where: { nome: string } }) =>
      args.where.nome === 'Lazer' ? null : { id: 1 }) as never);
    prisma.categoria.create.mockResolvedValue({} as never);
    prisma.categoria.update.mockResolvedValue({} as never);

    expect(await service.garantirCategoriasPadrao()).toBe(1);
  });

  it('as categorias de sistema não repetem nome', () => {
    const nomes = CATEGORIAS_PADRAO.map((c) => c.nome);
    expect(new Set(nomes).size).toBe(nomes.length);
  });
});
