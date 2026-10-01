import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { Withdrawal } from './entities/withdrawal.entity';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { WalletsService } from '../wallets/wallets.service';
import {
  WithdrawalStatus,
  PaymentProvider,
  DriverStatus,
  UserRole,
} from '../common/enums';
import { Driver } from '../drivers/entities/driver.entity';
import { User } from '../users/entities/user.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

@Injectable()
export class WithdrawalsService {
  constructor(
    @InjectRepository(Withdrawal)
    private readonly withdrawalRepository: Repository<Withdrawal>,
    private readonly walletsService: WalletsService,
    private readonly dataSource: DataSource,
  ) {}

  /**
   * Withdrawals are a driver-only, operational action.
   *
   * The controller's role decorator is not enough on its own: this check is the
   * one that holds even if the route is reached through another entry point. A
   * caller must be a DRIVER user, have a driver profile, and that profile must be
   * ACTIVE. User status itself is re-checked on every request by JwtStrategy, so
   * `user.status = ACTIVE` is already implied here.
   */
  private async assertOperationalDriver(userId: string): Promise<Driver> {
    const user = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: userId } });
    if (!user || user.role !== UserRole.DRIVER) {
      throw new DomainException(
        'Only drivers can perform withdrawals',
        HttpStatus.FORBIDDEN,
        ErrorCode.AUTH_FORBIDDEN,
      );
    }

    const driver = await this.dataSource
      .getRepository(Driver)
      .findOne({ where: { userId } });
    if (!driver) {
      throw new DomainException(
        'Driver not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.DRIVER_NOT_FOUND,
      );
    }

    if (driver.status !== DriverStatus.ACTIVE) {
      throw new DomainException(
        `Driver account is ${driver.status.toLowerCase()} and cannot withdraw funds`,
        HttpStatus.FORBIDDEN,
        ErrorCode.DRIVER_NOT_ACTIVE,
      );
    }

    return driver;
  }

  /**
   * Confirms an existing request under [idempotencyKey] is the same request.
   * A key reused with a different amount or destination is a conflict, never a
   * silent alias for the first operation.
   */
  private assertSameRequest(
    existing: Withdrawal,
    dto: RequestWithdrawalDto,
  ): Withdrawal {
    const samePayload =
      existing.amount === dto.amount &&
      existing.destinationType === dto.destinationType &&
      (existing.destination ?? null) === (dto.destination ?? null) &&
      (existing.destinationAccount ?? null) ===
        (dto.destinationAccount ?? null) &&
      existing.provider === (dto.provider ?? PaymentProvider.MOCK);

    if (!samePayload) {
      throw new DomainException(
        'This idempotency key was already used for a different withdrawal request',
        HttpStatus.CONFLICT,
        ErrorCode.IDEMPOTENCY_CONFLICT,
      );
    }

    return existing;
  }

  async requestWithdrawal(
    driverUserId: string,
    dto: RequestWithdrawalDto,
  ): Promise<Withdrawal> {
    await this.assertOperationalDriver(driverUserId);

    // Keys are scoped to the requesting driver: one driver's key is invisible to
    // every other driver.
    const existing = await this.withdrawalRepository.findOne({
      where: { userId: driverUserId, idempotencyKey: dto.idempotencyKey },
    });
    if (existing) return this.assertSameRequest(existing, dto);

    return this.dataSource.transaction(async (manager: EntityManager) => {
      const existingTx = await manager.findOne(Withdrawal, {
        where: { userId: driverUserId, idempotencyKey: dto.idempotencyKey },
      });
      if (existingTx) return this.assertSameRequest(existingTx, dto);

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
    await this.assertOperationalDriver(userId);

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
