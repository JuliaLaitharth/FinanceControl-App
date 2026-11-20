import { describe, expect, it } from '@jest/globals';
import { ValidationPipe } from '@nestjs/common';
import { LoginOAuthDto, TokenDto } from './oauth.controller';

// Mesmas opções do main.ts: sem decorator, o campo é descartado.
const pipe = new ValidationPipe({ whitelist: true, transform: true });
const passar = (valor: object, metatype: new () => object) =>
  pipe.transform(valor, { type: 'body', metatype });

describe('DTOs do OAuth sob o ValidationPipe global (whitelist)', () => {
  it('troca de código: code e redirect_uri chegam ao serviço', async () => {
    const dto = (await passar(
      { grant_type: 'authorization_code', code: 'abc', redirect_uri: 'https://x.com/cb' },
      TokenDto,
    )) as TokenDto;

    expect(dto.code).toBe('abc');
    expect(dto.redirect_uri).toBe('https://x.com/cb');
  });

  it('renovação: refresh_token chega ao serviço', async () => {
    const dto = (await passar({ grant_type: 'refresh_token', refresh_token: 'r1' }, TokenDto)) as TokenDto;
    expect(dto.refresh_token).toBe('r1');
  });

  it('credenciais da skill enviadas no corpo também chegam', async () => {
    const dto = (await passar(
      { grant_type: 'authorization_code', client_id: 'skill', client_secret: 'seg' },
      TokenDto,
    )) as TokenDto;
    expect(dto.client_id).toBe('skill');
    expect(dto.client_secret).toBe('seg');
  });

  it('campos desconhecidos continuam sendo descartados', async () => {
    const dto = (await passar({ grant_type: 'authorization_code', admin: true }, TokenDto)) as Record<string, unknown>;
    expect(dto.admin).toBeUndefined();
  });

  it('login da página de autorização mantém e-mail, senha, redirectUri e state', async () => {
    const dto = (await passar(
      { email: 'a@b.com', senha: 'x', redirectUri: 'https://x.com/cb', state: 's' },
      LoginOAuthDto,
    )) as LoginOAuthDto;
    expect(dto).toMatchObject({ email: 'a@b.com', senha: 'x', redirectUri: 'https://x.com/cb', state: 's' });
  });
});
