import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { AuditService } from '../audit/audit.service.js';
import { EncryptionService } from '../encryption/encryption.service.js';
import { PluggyAdapter } from '../pluggy/pluggy.adapter.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { FiltroTransacaoDto } from './dto/filtro-transacao.dto.js';

// Mapa de palavras-chave para auto-categorização (RF05 básico)
const KEYWORDS: Record<string, string[]> = {
  Alimentação: ['mercado', 'supermercado', 'restaurante', 'lanchonete', 'padaria', 'pizza', 'ifood', 'delivery', 'burguer'],
  Transporte: ['uber', '99pop', 'taxi', 'combustivel', 'gasolina', 'etanol', 'posto', 'estacionamento', 'onibus', 'metro'],
  Moradia: ['aluguel', 'condominio', 'iptu', 'energia', 'enel', 'cemig', 'sabesp', 'internet', 'compesa'],
  Saúde: ['farmacia', 'remedio', 'hospital', 'clinica', 'medico', 'exame', 'saude', 'drogaria'],
  Educação: ['escola', 'faculdade', 'curso', 'mensalidade', 'colegio', 'udemy', 'alura'],
  Lazer: ['cinema', 'teatro', 'show', 'netflix', 'spotify', 'amazon', 'steam', 'jogo', 'entretenimento', 'disney'],
  'Pix enviado': ['pix enviado', 'ted enviado', 'doc enviado'],
  'Pix recebido': ['pix recebido', 'ted recebido', 'doc recebido'],
  Renda: ['salario', 'folha pagamento'],
  Transferência: ['transferencia', 'transf'],
  Investimentos: ['investimento', 'aplicacao', 'resgate', 'fundo', 'cdb', 'tesouro'],
};

function normalizar(str: string): string {
  return str
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

@Injectable()
export class TransacaoService {
  private readonly logger = new Logger(TransacaoService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly pluggy: PluggyAdapter,
    private readonly encryption: EncryptionService,
    private readonly audit: AuditService,
  ) {}

  /** Lista transações do usuário com filtros e paginação. */
  async listar(usuarioId: number, filtro: FiltroTransacaoDto) {
    const page = filtro.page ?? 1;
    const limit = filtro.limit ?? 20;

    const where: Record<string, unknown> = {
      conta: { consentimento: { usuarioId, status: 'ATIVO' } },
    };
    if (filtro.de || filtro.ate) {
      where['data'] = {
        ...(filtro.de ? { gte: new Date(filtro.de) } : {}),
        ...(filtro.ate ? { lte: new Date(filtro.ate) } : {}),
      };
    }
    if (filtro.categoriaId) where['categoriaId'] = filtro.categoriaId;
    if (filtro.tipo) where['tipo'] = filtro.tipo;
    if (filtro.contaId) where['contaId'] = filtro.contaId;
    if (filtro.instituicaoId) {
      where['conta'] = {
        consentimento: { usuarioId, status: 'ATIVO', instituicaoId: filtro.instituicaoId },
      };
    }
    if (filtro.valorMin !== undefined || filtro.valorMax !== undefined) {
      where['valor'] = {
        ...(filtro.valorMin !== undefined ? { gte: filtro.valorMin } : {}),
        ...(filtro.valorMax !== undefined ? { lte: filtro.valorMax } : {}),
      };
    }

    const [dados, total] = await Promise.all([
      this.prisma.transacao.findMany({
        where: where as never,
        include: {
          categoria: { select: { nome: true, icone: true } },
          conta: {
            select: {
              numeroMascarado: true,
              consentimento: {
                include: { instituicao: { select: { nome: true } } },
              },
            },
          },
        },
        orderBy: { data: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.transacao.count({ where: where as never }),
    ]);

    return {
      dados,
      total,
      pagina: page,
      porPagina: limit,
      totalPaginas: Math.ceil(total / limit),
    };
  }

  /**
   * Sincroniza transações dos últimos 90 dias via Pluggy.
   * Aplica auto-categorização para transações novas.
   */
  async sincronizar(
    usuarioId: number,
    ip?: string,
  ): Promise<{ sincronizadas: number; novasIds: number[] }> {
    const [categorias, regrasUsuario] = await Promise.all([
      this.prisma.categoria.findMany({
        where: { padraoSistema: true },
        select: { id: true, nome: true },
      }),
      this.prisma.regraCategorizacao.findMany({
        where: { usuarioId },
        select: { palavra: true, categoriaId: true },
      }),
    ]);

    const consentimentos = await this.prisma.consentimento.findMany({
      where: { usuarioId, status: 'ATIVO' },
      include: { contas: true },
    });

    const noventa = new Date(Date.now() - 90 * 86_400_000);
    const hoje = new Date();
    let sincronizadas = 0;
    const novasIds: number[] = [];

    for (const c of consentimentos) {
      // Atualiza saldo das contas (RF03) — melhor esforço, não impede a sincronização de transações.
      try {
        const itemId = this.encryption.decrypt(c.itemIdPluggy);
        const contasPluggy = (await this.pluggy.buscarContas(itemId)) ?? [];
        for (const cp of contasPluggy) {
          await this.prisma.contaBancaria.updateMany({
            where: { idExternoPluggy: cp.id, consentimentoId: c.id },
            data: { saldoAtual: cp.balance, ultimaSincronizacao: new Date() },
          });
        }
      } catch (err) {
        this.logger.warn(`Erro ao atualizar saldos do consentimento ${c.id}: ${String(err)}`);
      }

      for (const conta of c.contas) {
        try {
          const txs = await this.pluggy.buscarTransacoes(
            conta.idExternoPluggy,
            noventa,
            hoje,
          );

          const existentes = new Set(
            (
              (await this.prisma.transacao.findMany({
                where: { idExternoPluggy: { in: txs.map((t: { id: string }) => t.id) } },
                select: { idExternoPluggy: true },
              })) ?? []
            ).map((e: { idExternoPluggy: string }) => e.idExternoPluggy),
          );

          for (const tx of txs) {
            const categoriaId = this.categorizarAuto(tx.description ?? '', categorias, regrasUsuario);
            const registro = await this.prisma.transacao.upsert({
              where: { idExternoPluggy: tx.id },
              create: {
                contaId: conta.id,
                idExternoPluggy: tx.id,
                descricao: tx.description ?? 'Sem descrição',
                // No Pluggy, o sinal de amount é a direção real do dinheiro (negativo = saída).
                // O campo `type` não serve: compras no cartão chegam como CREDIT com valor
                // negativo e seriam contadas como receita. Guardamos o valor em módulo.
                valor: Math.abs(tx.amount),
                tipo: tx.amount < 0 ? 'DEBIT' : tx.amount > 0 ? 'CREDIT' : tx.type,
                data: new Date(tx.date),
                metodoPagamento: (tx as Record<string, unknown>)['paymentData']
                  ? String(((tx as Record<string, unknown>)['paymentData'] as Record<string, unknown>)?.['paymentMethod'] ?? '')
                  : null,
                categoriaId,
              },
              update: {},
            });
            if (!existentes.has(tx.id) && registro?.id !== undefined) novasIds.push(registro.id);
            sincronizadas++;
          }

          await this.prisma.contaBancaria.update({
            where: { id: conta.id },
            data: { ultimaSincronizacao: new Date() },
          });
        } catch (err) {
          this.logger.warn(`Erro ao sincronizar conta ${conta.id}: ${String(err)}`);
        }
      }
    }

    await this.audit.registrar(usuarioId, 'SINCRONIZACAO_REALIZADA', 'transacao', ip);
    this.logger.log(`Sincronizadas ${sincronizadas} transações para usuário ${usuarioId}`);
    return { sincronizadas, novasIds };
  }

  /** Resumo mensal de receitas e despesas para o dashboard (RF09). */
  async resumoMensal(
    usuarioId: number,
    meses: number = 6,
    referencia?: string,
  ): Promise<{ meses: Array<{ mes: string; receitas: number; despesas: number; saldo: number }> }> {
    // `referencia` (AAAA-MM) é o último mês do gráfico; sem ela, o mês atual.
    const [ano, mes] = referencia ? referencia.split('-').map(Number) : [];
    const agora = referencia ? new Date(ano, mes - 1, 1) : new Date();
    const inicio = new Date(agora.getFullYear(), agora.getMonth() - (meses - 1), 1);
    const fim = new Date(agora.getFullYear(), agora.getMonth() + 1, 1);

    const transacoes = await this.prisma.transacao.findMany({
      where: {
        conta: { consentimento: { usuarioId, status: 'ATIVO' } },
        data: { gte: inicio, lt: fim },
      },
      select: { valor: true, tipo: true, data: true },
    });

    // Inicializa todos os meses com zero
    const mapa: Record<string, { receitas: number; despesas: number }> = {};
    for (let i = meses - 1; i >= 0; i--) {
      const d = new Date(agora.getFullYear(), agora.getMonth() - i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      mapa[key] = { receitas: 0, despesas: 0 };
    }

    for (const tx of transacoes) {
      const key = `${tx.data.getFullYear()}-${String(tx.data.getMonth() + 1).padStart(2, '0')}`;
      if (mapa[key]) {
        const valor = Number(tx.valor);
        if (tx.tipo === 'CREDIT') mapa[key].receitas += valor;
        else mapa[key].despesas += valor;
      }
    }

    const result = Object.entries(mapa).map(([mes, { receitas, despesas }]) => ({
      mes,
      receitas: Math.round(receitas * 100) / 100,
      despesas: Math.round(despesas * 100) / 100,
      saldo: Math.round((receitas - despesas) * 100) / 100,
    }));

    return { meses: result };
  }

  /**
   * Gastos por categoria no período [dataInicio, dataFim) — usado pelos relatórios
   * do app e pela Alexa Skill (ConsultarGastosIntent). Sem dataInicio, o mês atual;
   * sem dataFim, até hoje.
   *
   * As datas das transações são gravadas à meia-noite UTC, então o início do mês
   * padrão também é calculado em UTC (no fuso local do servidor, as compras do dia 1º
   * ficavam de fora).
   */
  async resumoCategorias(
    usuarioId: number,
    dataInicio?: string,
    dataFim?: string,
  ): Promise<{
    categorias: Array<{ nome: string; icone: string | null; total: number; quantidade: number }>;
  }> {
    const hoje = new Date();
    const inicio = dataInicio
      ? new Date(dataInicio)
      : new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth(), 1));
    const fim = dataFim ? new Date(dataFim) : null;
    if (Number.isNaN(inicio.getTime()) || (fim && Number.isNaN(fim.getTime()))) {
      throw new BadRequestException('Data inválida. Use o formato AAAA-MM-DD.');
    }

    const transacoes = await this.prisma.transacao.findMany({
      where: {
        conta: { consentimento: { usuarioId, status: 'ATIVO' } },
        tipo: 'DEBIT',
        data: { gte: inicio, ...(fim ? { lt: fim } : {}) },
      },
      include: { categoria: { select: { nome: true, icone: true } } },
    });

    const mapa = new Map<string, { icone: string | null; total: number; quantidade: number }>();
    for (const tx of transacoes) {
      const nome = tx.categoria?.nome ?? 'Outros';
      const item = mapa.get(nome) ?? { icone: tx.categoria?.icone ?? null, total: 0, quantidade: 0 };
      item.total += Number(tx.valor);
      item.quantidade += 1;
      mapa.set(nome, item);
    }

    const categorias = [...mapa.entries()]
      .map(([nome, v]) => ({
        nome,
        icone: v.icone,
        total: Math.round(v.total * 100) / 100,
        quantidade: v.quantidade,
      }))
      .sort((a, b) => b.total - a.total);

    return { categorias };
  }

  /** Override manual de categoria (RF05): marca categoriaAjustadaManualmente = true. */
  async ajustarCategoria(transacaoId: number, categoriaId: number, usuarioId: number) {
    const tx = await this.prisma.transacao.findFirst({
      where: {
        id: transacaoId,
        conta: { consentimento: { usuarioId, status: 'ATIVO' } },
      },
    });
    if (!tx) {
      const { NotFoundException } = await import('@nestjs/common');
      throw new NotFoundException('Transação não encontrada');
    }
    return this.prisma.transacao.update({
      where: { id: transacaoId },
      data: { categoriaId, categoriaAjustadaManualmente: true },
    });
  }

  private categorizarAuto(
    descricao: string,
    categorias: Array<{ id: number; nome: string }>,
    regrasUsuario: Array<{ palavra: string; categoriaId: number }> = [],
  ): number | null {
    const descNorm = normalizar(descricao);

    // Regras do usuário têm prioridade sobre as palavras-chave do sistema
    for (const regra of regrasUsuario) {
      if (descNorm.includes(normalizar(regra.palavra))) {
        return regra.categoriaId;
      }
    }

    for (const [nome, keywords] of Object.entries(KEYWORDS)) {
      if (keywords.some((kw) => descNorm.includes(kw))) {
        const cat = categorias.find((c) => c.nome === nome);
        if (cat) return cat.id;
      }
    }

    // Fallback: Outros
    return categorias.find((c) => c.nome === 'Outros')?.id ?? null;
  }
}
