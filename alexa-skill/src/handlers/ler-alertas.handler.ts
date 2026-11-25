import { HandlerInput, RequestHandler } from 'ask-sdk-core';
import { IntentRequest, Response } from 'ask-sdk-model';
import { FinanceApiService } from '../services/finance-api.service';
import { falaAlertas } from '../utils/fala-alertas';

/** "Ler meus alertas": o aviso proativo não leva texto, então a skill lê quando o usuário pede. */
export const LerAlertasHandler: RequestHandler = {
  canHandle(input: HandlerInput): boolean {
    const request = input.requestEnvelope.request;
    return (
      request.type === 'IntentRequest' &&
      (request as IntentRequest).intent.name === 'LerAlertasIntent'
    );
  },

  async handle(input: HandlerInput): Promise<Response> {
    const { accessToken } = input.requestEnvelope.context.System.user;

    if (!accessToken) {
      return input.responseBuilder
        .speak('Você precisa vincular sua conta no aplicativo FinanceControl para continuar.')
        .withLinkAccountCard()
        .getResponse();
    }

    try {
      const api = new FinanceApiService(accessToken);
      const alertas = await api.getAlertasNaoLidos();
      return input.responseBuilder
        .speak(falaAlertas(alertas.map((a) => a.mensagem)))
        .getResponse();
    } catch {
      return input.responseBuilder
        .speak('Não consegui acessar seus alertas no momento. Tente novamente em instantes.')
        .getResponse();
    }
  },
};
