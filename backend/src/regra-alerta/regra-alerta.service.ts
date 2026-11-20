import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { AuditService } from '../audit/audit.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { CreateRegraAlertaDto } from './dto/create-regra-alerta.dto.js';
import { UpdateRegraAlertaDto } from './dto/update-regra-alerta.dto.js';

@Injectable()
export class RegraAlertaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /** Regras que independem do formato do DTO: limite > 0 e categoria quando o tipo exige. */
  private validar(tipoEvento: string, valorLimite: unknown, categoriaId: unknown) {
    if (valorLimite === null || valorLimite === undefined || Number(valorLimite) <= 0) {
      throw new BadRequestException('Informe um valor limite maior que zero.');
    }
    if (tipoEvento === 'DESPESA_CATEGORIA' && (categoriaId === null || categoriaId === undefined)) {
      throw new BadRequestException('Escolha a categoria da regra.');
    }
  }

  async criar(dto: CreateRegraAlertaDto, usuarioId: number, ip?: string) {
    this.validar(dto.tipoEvento, dto.valorLimite, dto.categoriaId);
    const regra = await this.prisma.regraAlerta.create({
      data: {
        usuarioId,
        tipoEvento: dto.tipoEvento,
        operador: dto.operador ?? null,
        valorLimite: dto.valorLimite ?? null,
        // Só o tipo "despesa por categoria" usa categoria.
        categoriaId: dto.tipoEvento === 'DESPESA_CATEGORIA' ? (dto.categoriaId ?? null) : null,
        canal: dto.canal,
      },
    });
    await this.audit.registrar(usuarioId, 'REGRA_CRIADA', 'regra_alerta', ip);
    return regra;
  }

  async listar(usuarioId: number) {
    return this.prisma.regraAlerta.findMany({
      where: { usuarioId },
      include: { categoria: { select: { nome: true, icone: true } } },
      orderBy: { dataCriacao: 'desc' },
    });
  }

  async atualizar(
    id: number,
    dto: UpdateRegraAlertaDto,
    usuarioId: number,
    ip?: string,
  ) {
    const atual = await this.garantirProprietario(id, usuarioId);

    // Valida o estado final (regra existente + alterações), não só o que veio no corpo.
    const tipoFinal = dto.tipoEvento ?? atual.tipoEvento;
    const limiteFinal = dto.valorLimite !== undefined ? dto.valorLimite : atual.valorLimite;
    const categoriaFinal = dto.categoriaId !== undefined ? dto.categoriaId : atual.categoriaId;
    this.validar(tipoFinal, limiteFinal, categoriaFinal);

    const regra = await this.prisma.regraAlerta.update({
      where: { id },
      data: {
        ...(dto.tipoEvento ? { tipoEvento: dto.tipoEvento } : {}),
        ...(dto.operador !== undefined ? { operador: dto.operador } : {}),
        ...(dto.valorLimite !== undefined ? { valorLimite: dto.valorLimite } : {}),
        // Ao trocar para um tipo que não usa categoria, limpa a antiga.
        ...(tipoFinal !== 'DESPESA_CATEGORIA'
          ? { categoriaId: null }
          : dto.categoriaId !== undefined
            ? { categoriaId: dto.categoriaId }
            : {}),
        ...(dto.canal ? { canal: dto.canal } : {}),
        ...(dto.ativa !== undefined ? { ativa: dto.ativa } : {}),
      },
    });
    await this.audit.registrar(usuarioId, 'REGRA_ATUALIZADA', 'regra_alerta', ip);
    return regra;
  }

  async excluir(id: number, usuarioId: number, ip?: string): Promise<void> {
    await this.garantirProprietario(id, usuarioId);
    await this.prisma.regraAlerta.delete({ where: { id } });
    await this.audit.registrar(usuarioId, 'REGRA_EXCLUIDA', 'regra_alerta', ip);
  }

  private async garantirProprietario(id: number, usuarioId: number) {
    const regra = await this.prisma.regraAlerta.findUnique({ where: { id } });
    if (!regra) throw new NotFoundException('Regra de alerta não encontrada');
    if (regra.usuarioId !== usuarioId) throw new ForbiddenException();
    return regra;
  }
}
