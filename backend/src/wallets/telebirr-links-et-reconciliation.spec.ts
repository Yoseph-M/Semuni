import { Currency, PaymentProvider, TopUpIntentStatus } from '../common/enums';
import { ErrorCode } from '../common/error-codes';
import { TopUpService } from './top-up.service';
import { ExternalReceiptVerifier, VerifiedExternalPayment } from '../links-et/links-et.types';

describe('Telebirr + links.et Reconciliation (Section 49)', () => {
  let intents: Map<string, any>;
  let repo: any;
  let walletsService: any;
  let telebirrGateway: any;
  let linksEtVerifier: jest.Mocked<ExternalReceiptVerifier>;
  let topUpService: TopUpService;

  const TEST_USER = 'user-uuid-1';
  const TELEBIRR_ORDER_REF = 'SMN9876543210abcdef';
  const LINKS_ET_RECEIPT_ID = 'LET_REC_9876543210';
  const AMOUNT_MINOR = 20000; // 200.00 ETB in santim

  beforeEach(() => {
    intents = new Map();

    let idCounter = 1;
    repo = {
      findOne: jest.fn(async ({ where }) => {
        return (
          [...intents.values()].find((i) =>
            Object.entries(where).every(([k, v]) => i[k] === v),
          ) ?? null
        );
      }),
      find: jest.fn(async () => [...intents.values()]),
      create: jest.fn((x) => ({ id: `intent-uuid-${idCounter++}`, createdAt: new Date(), ...x })),
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

    let userBalance = 0;
    walletsService = {
      getWalletByUserId: jest.fn().mockImplementation(async () => ({
        id: 'wallet-uuid-1',
        userId: TEST_USER,
        balance: userBalance,
        currency: Currency.ETB,
      })),
      topUp: jest.fn().mockImplementation(async (_userId, amount, _ref) => {
        userBalance += amount;
        return {
          id: 'wallet-uuid-1',
          userId: TEST_USER,
          balance: userBalance,
          currency: Currency.ETB,
        };
      }),
    };

    telebirrGateway = {
      initiateTopUp: jest.fn().mockResolvedValue({
        providerReference: TELEBIRR_ORDER_REF,
        checkoutUrl: `https://telebirr.test/checkout?ref=${TELEBIRR_ORDER_REF}`,
      }),
      verifyTransaction: jest.fn(),
    };

    const registry = {
      get: (provider: string) => {
        if (provider === PaymentProvider.TELEBIRR) return telebirrGateway;
        throw new Error(`Unknown provider: ${provider}`);
      },
      defaultProvider: () => PaymentProvider.TELEBIRR,
    };

    linksEtVerifier = {
      verify: jest.fn(),
      verifyImage: jest.fn(),
    };

    const logger = { log: jest.fn(), warn: jest.fn(), error: jest.fn() };

    topUpService = new TopUpService(
      repo,
      walletsService,
      registry as any,
      logger as any,
      linksEtVerifier,
    );
  });

  it('reconciles delayed/lost Telebirr webhook via links.et receipt verification and prevents double-crediting', async () => {
    // 1. Step 1: Passenger initiates a top-up intent via Telebirr
    const intent = await topUpService.initiate(TEST_USER, {
      amount: AMOUNT_MINOR,
      idempotencyKey: 'idemp-topup-001',
      provider: PaymentProvider.TELEBIRR,
    });

    expect(intent.status).toBe(TopUpIntentStatus.PENDING);
    expect(intent.providerReference).toBe(TELEBIRR_ORDER_REF);
    expect(intent.amountMinor).toBe(AMOUNT_MINOR);
    expect(intent.currency).toBe(Currency.ETB);

    // 2. Telebirr payment completes off-platform, but webhook is delayed or dropped.
    // 3. User / system presents the links.et receipt for verification.
    const normalizedPayment: VerifiedExternalPayment = {
      provider: 'telebirr',
      providerReference: TELEBIRR_ORDER_REF,
      amountMinor: AMOUNT_MINOR,
      currency: Currency.ETB,
      status: 'SUCCESS',
      payerReference: '251911***456',
      destinationReference: 'SEMUNI_TRANSPORT',
      receiptReference: LINKS_ET_RECEIPT_ID,
      paymentDate: new Date(),
      source: 'links.et',
      resolvedUrl: 'https://links.et/r/telebirr-001',
      verifiedAt: new Date(),
    };

    linksEtVerifier.verify.mockResolvedValueOnce(normalizedPayment);

    // 4. Settle with external receipt
    const result = await topUpService.settleWithExternalReceipt(
      TEST_USER,
      intent.id,
      { reference: TELEBIRR_ORDER_REF },
    );

    // 5. Assert top-up is successfully settled and wallet credited exactly once
    expect(result.intent.status).toBe(TopUpIntentStatus.SUCCESS);
    expect(result.intent.receiptReference).toBe(LINKS_ET_RECEIPT_ID);
    expect(result.intent.providerReference).toBe(TELEBIRR_ORDER_REF);
    expect(result.wallet.balance).toBe(AMOUNT_MINOR);
    expect(walletsService.topUp).toHaveBeenCalledTimes(1);
    expect(walletsService.topUp).toHaveBeenCalledWith(
      TEST_USER,
      AMOUNT_MINOR,
      TELEBIRR_ORDER_REF,
    );

    // 6. Test Replay 1: Delayed Telebirr webhook eventually arrives
    // Settle by provider reference should return existing SUCCESS without double crediting
    telebirrGateway.verifyTransaction.mockResolvedValueOnce({
      verified: true,
      amountMinor: AMOUNT_MINOR,
      providerReference: TELEBIRR_ORDER_REF,
    });

    const webhookReplay = await topUpService.settleByProviderReference(
      TELEBIRR_ORDER_REF,
      PaymentProvider.TELEBIRR,
    );

    expect(webhookReplay.intent.status).toBe(TopUpIntentStatus.SUCCESS);
    expect(webhookReplay.wallet.balance).toBe(AMOUNT_MINOR); // Still 20000, not 40000
    expect(walletsService.topUp).toHaveBeenCalledTimes(1); // Still 1 call

    // 7. Test Replay 2: links.et receipt is replayed
    const receiptReplay = await topUpService.settleWithExternalReceipt(
      TEST_USER,
      intent.id,
      { reference: TELEBIRR_ORDER_REF },
    );

    expect(receiptReplay.intent.status).toBe(TopUpIntentStatus.SUCCESS);
    expect(receiptReplay.wallet.balance).toBe(AMOUNT_MINOR); // No increase
    expect(walletsService.topUp).toHaveBeenCalledTimes(1); // Still exactly 1 call
  });

  describe('Reconciliation Guardrails & Security', () => {
    it('rejects receipt if amount does not match intent', async () => {
      const intent = await topUpService.initiate(TEST_USER, {
        amount: AMOUNT_MINOR,
        idempotencyKey: 'idemp-topup-002',
        provider: PaymentProvider.TELEBIRR,
      });

      linksEtVerifier.verify.mockResolvedValueOnce({
        provider: 'telebirr',
        providerReference: TELEBIRR_ORDER_REF,
        amountMinor: 5000, // Different amount (50.00 ETB instead of 200.00 ETB)
        currency: Currency.ETB,
        status: 'SUCCESS',
        receiptReference: 'REC_MISMATCH_AMOUNT',
        paymentDate: new Date(),
        source: 'links.et',
        verifiedAt: new Date(),
      });

      await expect(
        topUpService.settleWithExternalReceipt(TEST_USER, intent.id, {
          reference: TELEBIRR_ORDER_REF,
        }),
      ).rejects.toMatchObject({
        code: ErrorCode.VALIDATION_ERROR,
      });

      expect(walletsService.topUp).not.toHaveBeenCalled();
    });

    it('rejects receipt if providerReference does not match intent', async () => {
      const intent = await topUpService.initiate(TEST_USER, {
        amount: AMOUNT_MINOR,
        idempotencyKey: 'idemp-topup-003',
        provider: PaymentProvider.TELEBIRR,
      });

      linksEtVerifier.verify.mockResolvedValueOnce({
        provider: 'telebirr',
        providerReference: 'DIFFERENT_ORDER_REF_999',
        amountMinor: AMOUNT_MINOR,
        currency: Currency.ETB,
        status: 'SUCCESS',
        receiptReference: 'REC_WRONG_REF',
        paymentDate: new Date(),
        source: 'links.et',
        verifiedAt: new Date(),
      });

      await expect(
        topUpService.settleWithExternalReceipt(TEST_USER, intent.id, {
          reference: TELEBIRR_ORDER_REF,
        }),
      ).rejects.toMatchObject({
        code: ErrorCode.VALIDATION_ERROR,
      });

      expect(walletsService.topUp).not.toHaveBeenCalled();
    });

    it('rejects receipt if receiptReference was already consumed by another top-up', async () => {
      // First top-up consumes the receipt
      const intent1 = await topUpService.initiate(TEST_USER, {
        amount: AMOUNT_MINOR,
        idempotencyKey: 'idemp-topup-004a',
        provider: PaymentProvider.TELEBIRR,
      });

      linksEtVerifier.verify.mockResolvedValueOnce({
        provider: 'telebirr',
        providerReference: intent1.providerReference!,
        amountMinor: AMOUNT_MINOR,
        currency: Currency.ETB,
        status: 'SUCCESS',
        receiptReference: 'STOLEN_OR_REUSED_RECEIPT_ID',
        paymentDate: new Date(),
        source: 'links.et',
        verifiedAt: new Date(),
      });

      await topUpService.settleWithExternalReceipt(TEST_USER, intent1.id, {
        reference: intent1.providerReference,
      });

      // Second top-up attempts to reuse the same receipt
      const intent2 = await topUpService.initiate('another-user-uuid', {
        amount: AMOUNT_MINOR,
        idempotencyKey: 'idemp-topup-004b',
        provider: PaymentProvider.TELEBIRR,
      });

      linksEtVerifier.verify.mockResolvedValueOnce({
        provider: 'telebirr',
        providerReference: intent2.providerReference!,
        amountMinor: AMOUNT_MINOR,
        currency: Currency.ETB,
        status: 'SUCCESS',
        receiptReference: 'STOLEN_OR_REUSED_RECEIPT_ID',
        paymentDate: new Date(),
        source: 'links.et',
        verifiedAt: new Date(),
      });

      await expect(
        topUpService.settleWithExternalReceipt('another-user-uuid', intent2.id, {
          reference: intent2.providerReference,
        }),
      ).rejects.toMatchObject({
        code: ErrorCode.PAYMENT_ALREADY_PROCESSED,
      });

      // Top-up for intent2 was NOT credited
      expect(walletsService.topUp).toHaveBeenCalledTimes(1);
    });
  });
});
