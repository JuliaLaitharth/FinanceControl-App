import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// RNF01 / HU11: o token da Alexa só consulta saldo, resumo de gastos e alertas (e registra o id Alexa).
const ROTAS_ALEXA: Array<{ metodo: string; caminho: string }> = [
  { metodo: 'GET', caminho: '/contas/saldo' },
  { metodo: 'GET', caminho: '/transacoes/resumo-categorias' },
  { metodo: 'GET', caminho: '/notificacoes' },
  { metodo: 'PATCH', caminho: '/auth/alexa-id' },
];

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser = { scope?: string }>(
    err: unknown,
    user: TUser,
    info: unknown,
    context: ExecutionContext,
    status?: unknown,
  ): TUser {
    const autenticado = super.handleRequest(err, user, info, context, status as never) as TUser;
    if ((autenticado as { scope?: string }).scope === 'alexa') {
      const req = context.switchToHttp().getRequest<{ method: string; originalUrl: string }>();
      const caminho = req.originalUrl.split('?')[0].replace(/\/+$/, '');
      const permitido = ROTAS_ALEXA.some((r) => r.metodo === req.method && r.caminho === caminho);
      if (!permitido) throw new ForbiddenException('Token da Alexa não autorizado para este recurso.');
    }
    return autenticado;
  }
}
