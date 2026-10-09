import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Settlement } from './entities/settlement.entity';
import { Withdrawal } from '../withdrawals/entities/withdrawal.entity';
import { WithdrawalStatus } from '../common/enums';

@Injectable()
export class SettlementsService {
  private readonly logger = new Logger(SettlementsService.name);

  constructor(
    @InjectRepository(Settlement)
    private readonly settlementRepository: Repository<Settlement>,
    private readonly dataSource: DataSource,
  ) {}

  async getMySettlements(driverUserId: string): Promise<Settlement[]> {
    return this.settlementRepository.find({
      where: { driverId: driverUserId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  async processPendingWithdrawals(): Promise<{ processedCount: number }> {
    let processedCount = 0;

    await this.dataSource.transaction(async (manager: EntityManager) => {
      const pendingWithdrawals = await manager.find(Withdrawal, {
        where: [
          { status: WithdrawalStatus.PENDING },
          { status: WithdrawalStatus.PROCESSING },
        ],
        lock: { mode: 'pessimistic_write' },
      });

      if (pendingWithdrawals.length === 0) {
        return;
      }

      for (const withdrawal of pendingWithdrawals) {
        withdrawal.status = WithdrawalStatus.SUCCESS;
        withdrawal.completedAt = new Date();
        withdrawal.externalReference =
          withdrawal.externalReference ||
          `BATCH-${Date.now()}-${withdrawal.id.slice(0, 8)}`;
        await manager.save(withdrawal);

        const settlementExists = await manager.findOne(Settlement, {
          where: { withdrawalId: withdrawal.id },
        });
        if (!settlementExists) {
          const settlement = manager.create(Settlement, {
            driverId: withdrawal.userId,
            withdrawalId: withdrawal.id,
            amount: withdrawal.amount,
            currency: withdrawal.currency,
            status: WithdrawalStatus.SUCCESS,
            externalReference: withdrawal.externalReference,
            completedAt: new Date(),
          });
          await manager.save(settlement);
        }

        processedCount++;
      }
    });

    this.logger.log(
      `Settlements batch: processed ${processedCount} pending withdrawals.`,
    );
    return { processedCount };
  }
}
