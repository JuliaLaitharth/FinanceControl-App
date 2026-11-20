import { describe, expect, it } from '@jest/globals';
import {
  clienteIdConfere,
  clienteValido,
  jsonSeguro,
  lerBasic,
  lerConfigOauth,
  redirectUriPermitido,
} from './alexa-oauth.config';
import { urlProactiveEvents } from '../alexa/alexa.service';

const PERMITIDOS = [
  'https://pitangui.amazon.com/api/skill/link/ABC',
  'https://layla.amazon.com/api/skill/link/ABC',
];

describe('redirectUriPermitido', () => {
  it('aceita só endereços exatos da lista', () => {
    expect(redirectUriPermitido(PERMITIDOS[0], PERMITIDOS)).toBe(true);
    expect(redirectUriPermitido(PERMITIDOS[1], PERMITIDOS)).toBe(true);
  });

  it.each([
    ['domínio do atacante', 'https://evil.example/api/skill/link/ABC'],
    ['prefixo igual com sufixo', 'https://pitangui.amazon.com/api/skill/link/ABC/../evil'],
    ['host parecido', 'https://pitangui.amazon.com.evil.example/api/skill/link/ABC'],
    ['http sem TLS', 'http://pitangui.amazon.com/api/skill/link/ABC'],
    ['esquema perigoso', 'javascript:alert(1)'],
    ['vazio', ''],
    ['lixo', 'não é url'],
  ])('rejeita %s', (_nome, uri) => {
    expect(redirectUriPermitido(uri, PERMITIDOS)).toBe(false);
  });

  it('sem lista configurada, rejeita tudo (seguro por padrão)', () => {
    expect(redirectUriPermitido(PERMITIDOS[0], [])).toBe(false);
  });

  it('lê a lista do ambiente ignorando espaços e itens vazios', () => {
    const cfg = lerConfigOauth((k) =>
      k === 'ALEXA_REDIRECT_URIS' ? ' https://a.com/x , ,https://b.com/y ' : undefined,
    );
    expect(cfg.redirectUris).toEqual(['https://a.com/x', 'https://b.com/y']);
  });
});

describe('credenciais do cliente', () => {
  const cfg = { clientId: 'skill', clientSecret: 'segredo', redirectUris: [] };

  it('exige id e secret corretos', () => {
    expect(clienteValido(cfg, 'skill', 'segredo')).toBe(true);
    expect(clienteValido(cfg, 'skill', 'errado')).toBe(false);
    expect(clienteValido(cfg, 'outro', 'segredo')).toBe(false);
    expect(clienteValido(cfg, undefined, undefined)).toBe(false);
  });

  it('sem configuração, nunca valida', () => {
    expect(clienteValido({ redirectUris: [] }, 'skill', 'segredo')).toBe(false);
    expect(clienteIdConfere({ redirectUris: [] }, 'skill')).toBe(false);
  });

  it('confere o client_id da tela de autorização', () => {
    expect(clienteIdConfere(cfg, 'skill')).toBe(true);
    expect(clienteIdConfere(cfg, 'x')).toBe(false);
  });

  it('lê o header HTTP Basic, inclusive com ":" no segredo', () => {
    const h = 'Basic ' + Buffer.from('skill:se:gredo').toString('base64');
    expect(lerBasic(h)).toEqual({ id: 'skill', secret: 'se:gredo' });
    expect(lerBasic(undefined)).toBeNull();
    expect(lerBasic('Bearer abc')).toBeNull();
    expect(lerBasic('Basic ' + Buffer.from('semdoispontos').toString('base64'))).toBeNull();
  });
});

describe('jsonSeguro', () => {
  it('impede fechar a tag <script> com o state', () => {
    const saida = jsonSeguro('</script><script>alert(1)</script>');
    expect(saida).not.toContain('</script>');
    expect(JSON.parse(saida.replace(/\\u003c/g, '<'))).toBe('</script><script>alert(1)</script>');
  });
});

describe('urlProactiveEvents', () => {
  it('usa o estágio de desenvolvimento por padrão e produção só com "live"', () => {
    expect(urlProactiveEvents(undefined)).toMatch(/\/stages\/development$/);
    expect(urlProactiveEvents('development')).toMatch(/\/stages\/development$/);
    expect(urlProactiveEvents('live')).toBe('https://api.amazonalexa.com/v1/proactiveEvents');
  });
});
