import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CATEGORIAS_PADRAO } from './categorias-padrao';

@Injectable()
export class CategoriaService implements OnModuleInit {
  private readonly logger = new Logger(CategoriaService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Garante as categorias padrão na subida. Um banco novo em produção não passa
   * pelo seed manual, e sem elas a categorização automática e os seletores do app
   * ficariam vazios. Idempotente: só cria o que falta e atualiza ícone/tipo.
   */
  async onModuleInit(): Promise<void> {
    await this.garantirCategoriasPadrao();
  }

  async garantirCategoriasPadrao(): Promise<number> {
    let criadas = 0;
    for (const cat of CATEGORIAS_PADRAO) {
      const existente = await this.prisma.categoria.findFirst({
        where: { nome: cat.nome, padraoSistema: true, usuarioId: null },
        select: { id: true },
      });
      if (existente) {
        await this.prisma.categoria.update({
          where: { id: existente.id },
          data: { icone: cat.icone, tipo: cat.tipo },
        });
      } else {
        await this.prisma.categoria.create({
          data: { nome: cat.nome, tipo: cat.tipo, icone: cat.icone, padraoSistema: true, usuarioId: null },
        });
        criadas++;
      }
    }
    if (criadas > 0) this.logger.log(`${criadas} categoria(s) padrão criada(s)`);
    return criadas;
  }

  /** Retorna categorias do sistema + categorias customizadas do usuário. */
  async listar(usuarioId: number) {
    return this.prisma.categoria.findMany({
      where: {
        OR: [{ padraoSistema: true }, { usuarioId }],
      },
      select: { id: true, nome: true, tipo: true, icone: true, padraoSistema: true },
      orderBy: [{ padraoSistema: 'desc' }, { nome: 'asc' }],
    });
  }
}
