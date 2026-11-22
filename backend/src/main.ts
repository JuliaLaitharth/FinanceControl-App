import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  // Atrás do proxy do Railway: usa o IP real do cliente (auditoria e limite de requisições).
  // Número de proxies confiáveis configurável; o padrão (1) serve para o Railway.
  app.set('trust proxy', Number(process.env.TRUST_PROXY_HOPS ?? 1));
  // CSP desligada: a API é JSON; a única página HTML (login do Account Linking) usa script
  // embutido. Os demais cabeçalhos de segurança do helmet ficam ativos.
  app.use(helmet({ contentSecurityPolicy: false }));
  // CORS fica desligado de propósito: o cliente é um app nativo, sem navegador.
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, transform: true }),
  );
  await app.listen(process.env.PORT ?? 3000);
}
void bootstrap();
