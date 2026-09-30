import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Withdrawal } from './entities/withdrawal.entity';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { WalletsService } from '../wallets/wallets.service';
import { WithdrawalStatus, PaymentProvider } from '../common/enums';

@Injectable()
export class WithdrawalsService {
  constructor(
    @InjectRepository(Withdrawal)
    private readonly withdrawalRepository: Repository<Withdrawal>,
    private readonly walletsService: WalletsService,
    private readonly dataSource: DataSource,
  ) {}

  async requestWithdrawal(
    driverUserId: string,
    dto: RequestWithdrawalDto,
  ): Promise<Withdrawal> {
    const existing = await this.withdrawalRepository.findOne({
      where: { idempotencyKey: dto.idempotencyKey },
    });
    if (existing) return existing;

    return this.dataSource.transaction(async (manager: EntityManager) => {
      const existingTx = await manager.findOne(Withdrawal, {
        where: { idempotencyKey: dto.idempotencyKey },
      });
      if (existingTx) return existingTx;

      const withdrawal = manager.create(Withdrawal, {
        userId: driverUserId,
        amount: dto.amount,
        destinationType: dto.destinationType,
        destination: dto.destination,
        destinationAccount: dto.destinationAccount,
        provider: dto.provider ?? PaymentProvider.MOCK,
        idempotencyKey: dto.idempotencyKey,
        status: WithdrawalStatus.PENDING,
      });
      const saved = await manager.save(withdrawal);

      try {
        await this.walletsService.debitForWithdrawal(
          manager,
          driverUserId,
          dto.amount,
          saved.id,
        );

        saved.status = WithdrawalStatus.PROCESSING;
        await manager.save(saved);

        setTimeout(async () => {
          try {
            await this.mockComplete(saved.id);
          } catch (_) {}
        }, 100);

        return saved;
      } catch (err) {
        try {
          saved.status = WithdrawalStatus.FAILED;
          await manager.save(saved);
        } catch (_u) {}
        throw err;
      }
    });
  }

  async getMyWithdrawals(userId: string): Promise<Withdrawal[]> {
    return this.withdrawalRepository.find({
      where: { userId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  private async mockComplete(withdrawalId: string): Promise<void> {
    await this.dataSource.transaction(async (manager: EntityManager) => {
      const w = await manager.findOne(Withdrawal, {
        where: { id: withdrawalId },
      });
      if (!w) return;
      w.status = WithdrawalStatus.SUCCESS;
      w.externalReference = `MOCK-SETTLE-${w.id}`;
      w.completedAt = new Date();
      await manager.save(w);
    });
  }
}
