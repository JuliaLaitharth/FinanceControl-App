import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { UnauthorizedException } from '@nestjs/common';
import { createHash } from 'crypto';
import { WebhookController } from './webhook.controller';

const SECRET = 'segredo-de-teste';
const ITEM_ID = 'item-123';

describe('WebhookController — autenticação por header secreto', () => {
  let add: jest.Mock;
  let findFirst: jest.Mock;
  let controller: WebhookController;

  beforeEach(() => {
    add = jest.fn(async () => undefined);
    findFirst = jest.fn(async () => ({ usuarioId: 7 }));
    controller = new WebhookController(
      { getOrThrow: () => SECRET } as never,
      { add } as never,
      { consentimento: { findFirst } } as never,
    );
  });

  it('rejeita quando o header está ausente', async () => {
    await expect(
      controller.handlePluggy({ event: 'item/updated', itemId: ITEM_ID }, undefined as never),
    ).rejects.toThrow(UnauthorizedException);
    expect(add).not.toHaveBeenCalled();
  });

  it('rejeita quando o segredo está errado', async () => {
    await expect(
      controller.handlePluggy({ event: 'item/updated', itemId: ITEM_ID }, 'errado'),
    ).rejects.toThrow(UnauthorizedException);
    expect(add).not.toHaveBeenCalled();
  });

  it('aceita o segredo correto e enfileira a sincronização do usuário', async () => {
    const res = await controller.handlePluggy({ event: 'item/updated', itemId: ITEM_ID }, SECRET);

    expect(res).toEqual({ received: true });
    expect(findFirst).toHaveBeenCalledWith({
      where: { itemIdHash: createHash('sha256').update(ITEM_ID).digest('hex') },
      select: { usuarioId: true },
    });
    expect(add).toHaveBeenCalledWith(
      'sync',
      { usuarioId: 7, event: 'item/updated' },
      expect.objectContaining({ attempts: 3 }),
    );
  });

  it('ignora itens sem consentimento correspondente', async () => {
    findFirst.mockImplementation(async () => null);
    await controller.handlePluggy({ event: 'item/updated', itemId: ITEM_ID }, SECRET);
    expect(add).not.toHaveBeenCalled();
  });
});
