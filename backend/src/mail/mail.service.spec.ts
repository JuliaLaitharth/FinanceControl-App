import { afterEach, beforeEach, describe, expect, it, jest } from '@jest/globals';
import { ConfigService } from '@nestjs/config';
import { MailService } from './mail.service';

const config = (valores: Record<string, string>) =>
  ({ get: (k: string) => valores[k] }) as unknown as ConfigService;

describe('MailService', () => {
  const fetchOriginal = global.fetch;
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });
  afterEach(() => {
    global.fetch = fetchOriginal;
  });

  it('não chama a API sem RESEND_API_KEY', async () => {
    await new MailService(config({})).enviarRecuperacaoSenha('a@b.com', 'ABCD-EFGH');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('envia o código pelo Resend com a chave e o remetente configurados', async () => {
    fetchMock.mockResolvedValue({ ok: true, status: 200 } as never);
    await new MailService(config({ RESEND_API_KEY: 're_x', MAIL_FROM: 'App <a@b.com>' })).enviarRecuperacaoSenha(
      'user@x.com',
      'ABCD-EFGH',
    );

    const [url, init] = fetchMock.mock.calls[0] as [string, { headers: Record<string, string>; body: string }];
    expect(url).toBe('https://api.resend.com/emails');
    expect(init.headers.Authorization).toBe('Bearer re_x');
    const corpo = JSON.parse(init.body) as { from: string; to: string[]; text: string };
    expect(corpo.from).toBe('App <a@b.com>');
    expect(corpo.to).toEqual(['user@x.com']);
    expect(corpo.text).toContain('ABCD-EFGH');
  });

  it('não lança erro se o Resend falhar (resposta genérica ao usuário)', async () => {
    fetchMock.mockRejectedValue(new Error('rede'));
    await expect(
      new MailService(config({ RESEND_API_KEY: 're_x' })).enviarRecuperacaoSenha('u@x.com', 'ABCD-EFGH'),
    ).resolves.toBeUndefined();
  });
});
