import { MiddlewareConsumer, Module, NestModule, RequestMethod } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import * as express from 'express';
import { OauthController } from './oauth.controller.js';
import { OauthService } from './oauth.service.js';

@Module({
  imports: [
    JwtModule.registerAsync({
      useFactory: (config: ConfigService) => ({
        // Sem valor padrão: um segredo público assinaria os tokens da Alexa.
        secret: config.getOrThrow<string>('JWT_SECRET'),
      }),
      inject: [ConfigService],
    }),
  ],
  controllers: [OauthController],
  providers: [OauthService],
  exports: [OauthService],
})
export class OauthModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    // Alexa POSTs to /oauth/token as application/x-www-form-urlencoded
    consumer
      .apply(express.urlencoded({ extended: false }))
      .forRoutes({ path: 'oauth/token', method: RequestMethod.POST });
  }
}
