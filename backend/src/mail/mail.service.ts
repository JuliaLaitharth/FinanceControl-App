import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Envio de e-mails transacionais pela API do Resend (https://resend.com).
 *
 * Variáveis: `RESEND_API_KEY` (chave de API) e `MAIL_FROM` (remetente, ex.:
 * `FinanceControl <onboarding@resend.dev>`). Sem `RESEND_API_KEY` nada é enviado:
 * em desenvolvimento o código é escrito no log; em produção só um aviso é registrado.
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);

  constructor(private readonly config: ConfigService) {}

  async enviarRecuperacaoSenha(email: string, codigo: string): Promise<void> {
    const assunto = 'FinanceControl — código para redefinir sua senha';
    const texto =
      `Seu código para redefinir a senha do FinanceControl é: ${codigo}\n\n` +
      'Abra o app, toque em "Esqueci minha senha" → "Já tenho o código" e informe o código e a nova senha.\n' +
      'O código vale por 30 minutos e só pode ser usado uma vez.\n\n' +
      'Se não foi você quem pediu, ignore este e-mail: sua senha continua a mesma.';
    const html =
      `<p>Seu código para redefinir a senha do <b>FinanceControl</b> é:</p>` +
      `<p style="font-size:26px;letter-spacing:3px"><b>${codigo}</b></p>` +
      `<p>Abra o app, toque em <i>Esqueci minha senha</i> → <i>Já tenho o código</i> e informe o código e a nova senha.<br>` +
      `O código vale por 30 minutos e só pode ser usado uma vez.</p>` +
      `<p style="color:#666">Se não foi você quem pediu, ignore este e-mail: sua senha continua a mesma.</p>`;

    await this.enviar(email, assunto, texto, html, codigo);
  }

  private async enviar(para: string, assunto: string, texto: string, html: string, codigoDev: string) {
    const apiKey = this.config.get<string>('RESEND_API_KEY');
    if (!apiKey) {
      if (process.env.NODE_ENV === 'production') {
        this.logger.warn('RESEND_API_KEY não configurada: e-mail de recuperação NÃO enviado.');
      } else {
        this.logger.log(`[DEV] E-mail para ${para}: código ${codigoDev}`);
      }
      return;
    }

    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: this.config.get<string>('MAIL_FROM') ?? 'FinanceControl <onboarding@resend.dev>',
          to: [para],
          subject: assunto,
          text: texto,
          html,
        }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) {
        // Não repassa o corpo da resposta (pode ecoar dados); só o status.
        this.logger.error(`Resend recusou o e-mail (HTTP ${res.status}).`);
      }
    } catch (erro) {
      this.logger.error(`Falha ao enviar e-mail: ${(erro as Error).message}`);
    }
  }
}
