import { createHash, timingSafeEqual } from 'crypto';

/**
 * Configuração do Account Linking da Alexa.
 *
 * Seguro por padrão: sem ALEXA_OAUTH_CLIENT_ID/SECRET e sem ALEXA_REDIRECT_URIS
 * nenhuma vinculação é aceita (o endpoint /oauth/authorize é público, então um
 * redirect_uri livre permitiria roubar o código de acesso de quem faz login).
 */
export interface AlexaOauthConfig {
  clientId?: string;
  clientSecret?: string;
  /** Redirect URLs exibidas pelo console da Alexa (comparação exata). */
  redirectUris: string[];
}

export const lerConfigOauth = (get: (chave: string) => string | undefined): AlexaOauthConfig => ({
  clientId: get('ALEXA_OAUTH_CLIENT_ID') || undefined,
  clientSecret: get('ALEXA_OAUTH_CLIENT_SECRET') || undefined,
  redirectUris: (get('ALEXA_REDIRECT_URIS') ?? '')
    .split(',')
    .map((u) => u.trim())
    .filter(Boolean),
});

/** Comparação em tempo constante, sem vazar o tamanho do segredo. */
const igual = (a: string, b: string): boolean =>
  timingSafeEqual(createHash('sha256').update(a).digest(), createHash('sha256').update(b).digest());

/** Só https e só endereços exatos da lista configurada. */
export const redirectUriPermitido = (uri: string | undefined, permitidos: string[]): boolean => {
  if (!uri) return false;
  try {
    if (new URL(uri).protocol !== 'https:') return false;
  } catch {
    return false;
  }
  return permitidos.includes(uri);
};

export const clienteIdConfere = (cfg: AlexaOauthConfig, clientId: string | undefined): boolean =>
  !!cfg.clientId && !!clientId && igual(clientId, cfg.clientId);

export const clienteValido = (
  cfg: AlexaOauthConfig,
  clientId: string | undefined,
  clientSecret: string | undefined,
): boolean =>
  !!cfg.clientId &&
  !!cfg.clientSecret &&
  !!clientId &&
  !!clientSecret &&
  igual(clientId, cfg.clientId) &&
  igual(clientSecret, cfg.clientSecret);

/** Lê `Authorization: Basic base64(client_id:client_secret)` (esquema HTTP_BASIC da Alexa). */
export const lerBasic = (header: string | undefined): { id: string; secret: string } | null => {
  const m = /^Basic\s+(.+)$/i.exec(header ?? '');
  if (!m) return null;
  const texto = Buffer.from(m[1]!, 'base64').toString('utf8');
  const i = texto.indexOf(':');
  if (i < 0) return null;
  return { id: texto.slice(0, i), secret: texto.slice(i + 1) };
};

/** JSON seguro para embutir em <script>: `<` vira \\u003c e impede fechar a tag. */
export const jsonSeguro = (valor: unknown): string =>
  JSON.stringify(valor)
    .replace(/</g, '\\u003c')
    // separadores de linha Unicode quebram literais JS em navegadores antigos
    .split(String.fromCharCode(0x2028))
    .join('\\u2028')
    .split(String.fromCharCode(0x2029))
    .join('\\u2029');
