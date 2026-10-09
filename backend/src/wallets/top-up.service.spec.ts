import { HttpStatus } from '@nestjs/common';
import { TopUpService } from './top-up.service';
import { ErrorCode } from '../common/error-codes';
import { PaymentProvider, TopUpIntentStatus } from '../common/enums';

describe('TopUpService', () => {
  let intents: Map<string, any>;
  let repo: any;
  let walletsService: any;
  let gateway: any;
  let service: TopUpService;

  const pendingIntent = (overrides: Record<string, unknown> = {}) => {
    const intent = {
      id: 'intent-1',
      userId: 'user-1',
      amountMinor: 1250,
      currency: 'ETB',
      provider: PaymentProvider.TELEBIRR,
      status: TopUpIntentStatus.PENDING,
      providerReference: 'SMN1',
      idempotencyKey: 'k',
      createdAt: new Date(Date.now() - 30 * 60_000),
      ...overrides,
    };
    intents.set(intent.id, intent);
    return intent;
  };

  beforeEach(() => {
    intents = new Map();
    repo = {
      findOne: jest.fn(async ({ where }) =>
        [...intents.values()].find((i) =>
          Object.entries(where).every(([k, v]) => i[k] === v),
        ) ?? null,
      ),
      find: jest.fn(async () => [...intents.values()].filter((i) => i.status === TopUpIntentStatus.PENDING)),
      create: jest.fn((x) => ({ id: 'intent-new', createdAt: new Date(), ...x })),
      save: jest.fn(async (x) => {
        intents.set(x.id, x);
        return x;
      }),
      update: jest.fn(async ({ id, status }, patch) => {
        const i = intents.get(id);
        if (!i || i.status !== status) return { affected: 0 };
        Object.assign(i, patch);
        return { affected: 1 };
      }),
    };
    walletsService = {
      getWalletByUserId: jest.fn().mockResolvedValue({ balance: 0 }),
      topUp: jest.fn().mockResolvedValue({ balance: 1250 }),
    };
    gateway = {
      initiateTopUp: jest.fn(),
      verifyTransaction: jest.fn(),
    };
    const registry = {
      get: () => gateway,
      defaultProvider: () => PaymentProvider.TELEBIRR,
    };
    const logger = { log: jest.fn(), warn: jest.fn(), error: jest.fn() };
    service = new TopUpService(repo, walletsService, registry as any, logger as any);
  });

  it('uses the configured provider by default and stores the checkout URL', async () => {
    gateway.initiateTopUp.mockResolvedValue({
      providerReference: 'SMN1',
      checkoutUrl: 'https://checkout',
    });
    const intent = await service.initiate('user-1', { amount: 1250, idempotencyKey: 'k' } as any);
    expect(intent).toMatchObject({
      provider: PaymentProvider.TELEBIRR,
      providerReference: 'SMN1',
      checkoutUrl: 'https://checkout',
      status: TopUpIntentStatus.PENDING,
    });
  });

  it('closes the intent as FAILED when the provider cannot create the order', async () => {
    gateway.initiateTopUp.mockRejectedValue(new Error('down'));
    await expect(
      service.initiate('user-1', { amount: 1250, idempotencyKey: 'k' } as any),
    ).rejects.toThrow('down');
    expect(intents.get('intent-new').status).toBe(TopUpIntentStatus.FAILED);
  });

  it('credits exactly the confirmed amount', async () => {
    pendingIntent();
    gateway.verifyTransaction.mockResolvedValue({ verified: true, amountMinor: 1250, providerReference: 'SMN1' });
    const { intent } = await service.settleByProviderReference('SMN1', PaymentProvider.TELEBIRR);
    expect(intent.status).toBe(TopUpIntentStatus.SUCCESS);
    expect(walletsService.topUp).toHaveBeenCalledWith('user-1', 1250, 'SMN1');
  });

  it('keeps a pending payment PENDING and credits nothing', async () => {
    pendingIntent();
    gateway.verifyTransaction.mockResolvedValue({ verified: false, pending: true, providerReference: 'SMN1' });
    await expect(
      service.settleByProviderReference('SMN1', PaymentProvider.TELEBIRR),
    ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_PENDING, status: HttpStatus.CONFLICT });
    expect(intents.get('intent-1').status).toBe(TopUpIntentStatus.PENDING);
    expect(walletsService.topUp).not.toHaveBeenCalled();
  });

  it('refuses to credit when the confirmed amount differs', async () => {
    pendingIntent();
    gateway.verifyTransaction.mockResolvedValue({ verified: true, amountMinor: 1, providerReference: 'SMN1' });
    await expect(
      service.settleByProviderReference('SMN1', PaymentProvider.TELEBIRR),
    ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_FAILED });
    expect(intents.get('intent-1').status).toBe(TopUpIntentStatus.FAILED);
    expect(walletsService.topUp).not.toHaveBeenCalled();
  });

  it('does not let one provider settle another provider’s intent', async () => {
    pendingIntent();
    await expect(
      service.settleByProviderReference('SMN1', PaymentProvider.MOCK),
    ).rejects.toMatchObject({ code: ErrorCode.PAYMENT_NOT_FOUND });
  });

  it('reconciles: settles paid, keeps fresh pending, expires old pending', async () => {
    pendingIntent({ id: 'paid', providerReference: 'P' });
    pendingIntent({ id: 'waiting', providerReference: 'W' });
    pendingIntent({ id: 'old', providerReference: 'O', createdAt: new Date(Date.now() - 2 * 86_400_000) });
    gateway.verifyTransaction.mockImplementation(async (ref: string) =>
      ref === 'P'
        ? { verified: true, amountMinor: 1250, providerReference: ref }
        : { verified: false, pending: true, providerReference: ref },
    );

    const summary = await service.reconcilePending({ olderThanMinutes: 10, expireAfterMinutes: 1440 });

    expect(summary).toMatchObject({ checked: 3, settled: 1, stillPending: 1, expired: 1, errors: 0 });
    expect(intents.get('paid').status).toBe(TopUpIntentStatus.SUCCESS);
    expect(intents.get('waiting').status).toBe(TopUpIntentStatus.PENDING);
    expect(intents.get('old').status).toBe(TopUpIntentStatus.EXPIRED);
    expect(walletsService.topUp).toHaveBeenCalledTimes(1);
  });
});
