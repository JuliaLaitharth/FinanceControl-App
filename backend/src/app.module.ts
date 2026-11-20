import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AlexaModule } from './alexa/alexa.module';
import { AuditModule } from './audit/audit.module';
import { LgpdModule } from './lgpd/lgpd.module';
import { AuthModule } from './auth/auth.module';
import { CategoriaModule } from './categoria/categoria.module';
import { ConsentimentoModule } from './consentimento/consentimento.module';
import { ContaModule } from './conta/conta.module';
import { EncryptionModule } from './encryption/encryption.module';
import { FcmModule } from './fcm/fcm.module';
import { NotificacaoModule } from './notificacao/notificacao.module';
import { OauthModule } from './oauth/oauth.module';
import { RegraCategorizacaoModule } from './regra-categorizacao/regra-categorizacao.module';
import { PluggyModule } from './pluggy/pluggy.module';
import { PrismaModule } from './prisma/prisma.module';
import { RegraAlertaModule } from './regra-alerta/regra-alerta.module';
import { TransacaoModule } from './transacao/transacao.module';
import { WebhookModule } from './webhook/webhook.module';
import { WorkerModule } from './worker/worker.module';
import { redisConnection } from './redis/redis.config';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    BullModule.forRootAsync({
      useFactory: (config: ConfigService) => ({
        connection: redisConnection((k) => config.get<string>(k)),
      }),
      inject: [ConfigService],
    }),
    PrismaModule,
    EncryptionModule,
    AuditModule,
    FcmModule,
    AlexaModule,
    AuthModule,
    PluggyModule,
    ConsentimentoModule,
    ContaModule,
    WebhookModule,
    CategoriaModule,
    TransacaoModule,
    RegraAlertaModule,
    NotificacaoModule,
    OauthModule,
    LgpdModule,
    RegraCategorizacaoModule,
    WorkerModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
