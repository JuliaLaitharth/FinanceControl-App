import { InjectQueue } from '@nestjs/bullmq';
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { Queue } from 'bullmq';
import { IsInt, Min } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';

class AjustarCategoriaDto {
  @IsInt()
  @Min(1)
  categoriaId!: number;
}
import { FiltroTransacaoDto } from './dto/filtro-transacao.dto.js';
import { PLUGGY_SYNC_QUEUE, PluggySyncJobData } from '../worker/worker.processor.js';
import { TransacaoService } from './transacao.service.js';

@Controller('transacoes')
@UseGuards(JwtAuthGuard)
export class TransacaoController {
  constructor(
    private readonly service: TransacaoService,
    @InjectQueue(PLUGGY_SYNC_QUEUE) private readonly syncQueue: Queue<PluggySyncJobData>,
  ) {}

  @Get()
  listar(
    @Request() req: { user: { sub: number } },
    @Query() filtro: FiltroTransacaoDto,
  ) {
    return this.service.listar(req.user.sub, filtro);
  }

  @Get('resumo-mensal')
  resumoMensal(
    @Request() req: { user: { sub: number } },
    @Query('meses') meses?: string,
    @Query('referencia') referencia?: string,
  ) {
    const n = meses ? Math.min(Math.max(parseInt(meses) || 6, 1), 12) : 6;
    if (referencia !== undefined && !/^\d{4}-(0[1-9]|1[0-2])$/.test(referencia)) {
      throw new BadRequestException('referencia deve estar no formato AAAA-MM');
    }
    return this.service.resumoMensal(req.user.sub, n, referencia);
  }

  @Get('resumo-categorias')
  resumoCategorias(
    @Request() req: { user: { sub: number } },
    @Query('dataInicio') dataInicio?: string,
    @Query('dataFim') dataFim?: string,
  ) {
    return this.service.resumoCategorias(req.user.sub, dataInicio, dataFim);
  }

  @Patch(':id/categoria')
  ajustarCategoria(
    @Request() req: { user: { sub: number } },
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: AjustarCategoriaDto,
  ) {
    return this.service.ajustarCategoria(id, dto.categoriaId, req.user.sub);
  }

  @Post('sincronizar')
  @HttpCode(HttpStatus.OK)
  /**
   * Pede uma sincronização pelo mesmo caminho do webhook: o worker busca as transações novas e
   * avalia as regras de alerta (push e Alexa). Responde na hora; o app recarrega em seguida.
   */
  async sincronizar(@Request() req: { user: { sub: number } }) {
    await this.syncQueue.add(
      'sync',
      { usuarioId: req.user.sub, event: 'manual' },
      { attempts: 3, backoff: { type: 'exponential', delay: 5_000 }, removeOnComplete: 100, removeOnFail: 50 },
    );
    return { enfileirada: true };
  }
}
