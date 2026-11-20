/**
 * Conexão do Redis (BullMQ).
 *
 * Aceita REDIS_URL (formato dos serviços gerenciados: redis://usuario:senha@host:porta
 * ou rediss:// para TLS) e, se ela não existir, REDIS_HOST/REDIS_PORT/REDIS_PASSWORD
 * (desenvolvimento local, sem senha).
 */
export interface RedisConnection {
  host: string;
  port: number;
  username?: string;
  password?: string;
  tls?: Record<string, never>;
}

export const redisConnection = (get: (chave: string) => string | undefined): RedisConnection => {
  const url = get('REDIS_URL');
  if (url) {
    const u = new URL(url);
    return {
      host: u.hostname,
      port: Number(u.port || 6379),
      ...(u.username ? { username: decodeURIComponent(u.username) } : {}),
      ...(u.password ? { password: decodeURIComponent(u.password) } : {}),
      ...(u.protocol === 'rediss:' ? { tls: {} } : {}),
    };
  }
  return {
    host: get('REDIS_HOST') || 'localhost',
    port: Number(get('REDIS_PORT') || 6379),
    ...(get('REDIS_PASSWORD') ? { password: get('REDIS_PASSWORD') } : {}),
  };
};
