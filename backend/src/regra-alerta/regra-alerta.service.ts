import {
  BadRequestException,
  ConflictException,
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

  /** Regras que independem do formato do DTO: limite, categoria e conta conforme o tipo. */
  private validar(tipoEvento: string, valorLimite: unknown, categoriaId: unknown) {
    const ehPix = tipoEvento === 'PIX_RECEBIDO' || tipoEvento === 'PIX_ENVIADO';
    const semLimite = valorLimite === null || valorLimite === undefined;
    // No Pix o limite é opcional (sem limite = avisa em qualquer Pix).
    if (!(ehPix && semLimite) && (semLimite || Number(valorLimite) <= 0)) {
      throw new BadRequestException('Informe um valor limite maior que zero.');
    }
    if (tipoEvento === 'DESPESA_CATEGORIA' && (categoriaId === null || categoriaId === undefined)) {
      throw new BadRequestException('Escolha a categoria da regra.');
    }
  }

  /** Saldo mínimo é por conta: a conta precisa ser do usuário e ter no máximo um alerta. */
  private async validarConta(usuarioId: number, contaId: number | null | undefined, ignorarRegraId?: number) {
    if (contaId === null || contaId === undefined) {
      throw new BadRequestException('Escolha a conta do alerta de saldo mínimo.');
    }
    const conta = await this.prisma.contaBancaria.findFirst({
      where: { id: contaId, consentimento: { usuarioId, status: 'ATIVO' } },
      select: { id: true },
    });
    if (!conta) throw new BadRequestException('Conta não encontrada.');
    const duplicada = await this.prisma.regraAlerta.findFirst({
      where: {
        usuarioId,
        tipoEvento: 'SALDO_MINIMO',
        contaId,
        ...(ignorarRegraId ? { id: { not: ignorarRegraId } } : {}),
      },
      select: { id: true },
    });
    if (duplicada) throw new ConflictException('Já existe um alerta de saldo mínimo para esta conta.');
  }

  async criar(dto: CreateRegraAlertaDto, usuarioId: number, ip?: string) {
    this.validar(dto.tipoEvento, dto.valorLimite, dto.categoriaId);
    if (dto.tipoEvento === 'SALDO_MINIMO') await this.validarConta(usuarioId, dto.contaId);
    const regra = await this.prisma.regraAlerta.create({
      data: {
        usuarioId,
        tipoEvento: dto.tipoEvento,
        operador: dto.operador ?? null,
        valorLimite: dto.valorLimite ?? null,
        // Só o tipo "despesa por categoria" usa categoria.
        categoriaId: dto.tipoEvento === 'DESPESA_CATEGORIA' ? (dto.categoriaId ?? null) : null,
        contaId: dto.tipoEvento === 'SALDO_MINIMO' ? (dto.contaId ?? null) : null,
        canal: dto.canal,
      },
    });
    await this.audit.registrar(usuarioId, 'REGRA_CRIADA', 'regra_alerta', ip);
    return regra;
  }

  async listar(usuarioId: number) {
    return this.prisma.regraAlerta.findMany({
      where: { usuarioId },
      include: {
        categoria: { select: { nome: true, icone: true } },
        conta: { select: { id: true, tipo: true, numeroMascarado: true } },
      },
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

    // Regras antigas de saldo mínimo (sem conta) continuam válidas até serem editadas.
    const contaFinal = dto.contaId !== undefined ? dto.contaId : atual.contaId;
    if (tipoFinal === 'SALDO_MINIMO' && (dto.tipoEvento || dto.contaId !== undefined)) {
      await this.validarConta(usuarioId, contaFinal, id);
    }

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
        ...(tipoFinal !== 'SALDO_MINIMO'
          ? { contaId: null }
          : dto.contaId !== undefined
            ? { contaId: dto.contaId }
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
