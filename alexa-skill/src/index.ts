import { DefaultApiClient, SkillBuilders } from 'ask-sdk-core';
import { LaunchRequestHandler } from './handlers/launch.handler';
import { ConsultarSaldoHandler } from './handlers/consultar-saldo.handler';
import { ConsultarGastosHandler } from './handlers/consultar-gastos.handler';
import { HelpHandler, CancelAndStopHandler, SessionEndedHandler, ErrorHandler } from './handlers/common.handlers';

const skill = SkillBuilders.custom()
  .addRequestHandlers(
    LaunchRequestHandler,
    ConsultarSaldoHandler,
    ConsultarGastosHandler,
    HelpHandler,
    CancelAndStopHandler,
    SessionEndedHandler,
  )
  .addErrorHandlers(ErrorHandler)
  .withApiClient(new DefaultApiClient())
  .create();

/**
 * Handler da Lambda (dist/index.handler).
 *
 * Não usamos `.lambda()` do SDK: ele devolve um handler no estilo *callback*, que os
 * runtimes novos da AWS (Node.js 24+) não suportam mais — a função retorna vazio e a
 * Alexa responde "Um problema ocorreu com a resposta da Skill". Aqui o handler é
 * assíncrono e retorna a resposta, o que funciona em qualquer versão.
 */
export const handler = (event: Parameters<typeof skill.invoke>[0], context?: unknown) =>
  skill.invoke(event, context);
