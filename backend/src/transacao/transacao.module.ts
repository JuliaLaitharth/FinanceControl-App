import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { PluggyModule } from '../pluggy/pluggy.module.js';
import { PLUGGY_SYNC_QUEUE } from '../worker/worker.processor.js';
import { TransacaoController } from './transacao.controller.js';
import { TransacaoService } from './transacao.service.js';

@Module({
  imports: [PluggyModule, AuditModule, BullModule.registerQueue({ name: PLUGGY_SYNC_QUEUE })],
  controllers: [TransacaoController],
  providers: [TransacaoService],
  exports: [TransacaoService],
})
export class TransacaoModule {}
