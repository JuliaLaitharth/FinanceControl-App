import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { PLUGGY_SYNC_QUEUE } from '../worker/worker.processor.js';
import { ConsentimentoController } from './consentimento.controller';
import { ConsentimentoService } from './consentimento.service';

@Module({
  imports: [
    PluggyModule,
    AuditModule,
    BullModule.registerQueue({ name: PLUGGY_SYNC_QUEUE }),
  ],
  controllers: [ConsentimentoController],
  providers: [ConsentimentoService],
  exports: [ConsentimentoService],
})
export class ConsentimentoModule {}
