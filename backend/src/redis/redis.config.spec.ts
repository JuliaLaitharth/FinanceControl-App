import { describe, expect, it } from '@jest/globals';
import { redisConnection } from './redis.config';

const env = (vars: Record<string, string>) => (k: string) => vars[k];

describe('redisConnection', () => {
  it('desenvolvimento: host e porta, sem senha', () => {
    expect(redisConnection(env({ REDIS_HOST: 'localhost', REDIS_PORT: '6379' }))).toEqual({
      host: 'localhost',
      port: 6379,
    });
  });

  it('sem nada configurado usa localhost:6379', () => {
    expect(redisConnection(env({}))).toEqual({ host: 'localhost', port: 6379 });
  });

  it('aceita senha separada (REDIS_PASSWORD)', () => {
    expect(redisConnection(env({ REDIS_HOST: 'h', REDIS_PASSWORD: 's' }))).toMatchObject({ password: 's' });
  });

  it('REDIS_URL com senha: extrai host, porta, usuário e senha', () => {
    expect(redisConnection(env({ REDIS_URL: 'redis://default:abc123@redis.internal:6380' }))).toEqual({
      host: 'redis.internal',
      port: 6380,
      username: 'default',
      password: 'abc123',
    });
  });

  it('rediss:// liga o TLS', () => {
    expect(redisConnection(env({ REDIS_URL: 'rediss://:senha@x.upstash.io:6379' }))).toMatchObject({
      host: 'x.upstash.io',
      password: 'senha',
      tls: {},
    });
  });

  it('decodifica caracteres especiais da senha', () => {
    expect(redisConnection(env({ REDIS_URL: 'redis://u:p%40ss%2Fw@h:1' }))).toMatchObject({ password: 'p@ss/w' });
  });

  it('REDIS_URL tem prioridade sobre REDIS_HOST', () => {
    expect(redisConnection(env({ REDIS_URL: 'redis://a:1', REDIS_HOST: 'b' })).host).toBe('a');
  });
});
