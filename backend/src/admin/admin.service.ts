import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from '../users/entities/user.entity';
import { Driver } from '../drivers/entities/driver.entity';
import { Trip } from '../trips/entities/trip.entity';
import { Payment } from '../payments/entities/payment.entity';
import { Wallet } from '../wallets/entities/wallet.entity';
import {
  DriverStatus,
  PaymentRecordStatus,
  PaymentStatus,
  UserRole,
} from '../common/enums';
import { CreateAdminUserDto, UpdateAdminUserDto } from './dto/admin-user.dto';
import { UserStatus } from '../common/enums';
import { UsersService } from '../users/users.service';

/** Read-only operational views for administrators. Financial writes remain in
 * their respective domain use-cases (payments, top-ups and withdrawals). */
@Injectable()
export class AdminService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    @InjectRepository(Driver) private readonly drivers: Repository<Driver>,
    @InjectRepository(Trip) private readonly trips: Repository<Trip>,
    @InjectRepository(Payment) private readonly payments: Repository<Payment>,
    @InjectRepository(Wallet) private readonly wallets: Repository<Wallet>,
    private readonly usersService: UsersService,
  ) {}

  async listUsers() {
    const users = await this.users.find({ order: { createdAt: 'DESC' } });
    return users.map((user) => this.safeUser(user));
  }

  async createUser(dto: CreateAdminUserDto) {
    const user = await this.usersService.create({
      username: dto.username, passwordHash: dto.password, role: dto.role,
      status: dto.status ?? UserStatus.ACTIVE, phone: dto.phone, email: dto.email,
    });
    return this.safeUser(user);
  }

  async updateUser(id: string, dto: UpdateAdminUserDto) {
    const user = await this.usersService.findById(id);
    if (!user) throw new Error('User not found');
    const { password, ...fields } = dto;
    await this.users.update(id, fields);
    if (password) await this.usersService.setPassword(id, password);
    return this.safeUser((await this.usersService.findById(id))!);
  }

  async removeUser(id: string, actorId: string) {
    if (id === actorId) throw new Error('You cannot delete your own admin account');
    const user = await this.usersService.findById(id);
    if (!user) throw new Error('User not found');
    // User rows are referenced by trips, payments, wallets and ledger entries.
    // Keep those records auditable and make admin deletion a reversible
    // deactivation instead of a destructive hard delete.
    await this.users.update(id, { status: UserStatus.INACTIVE });
    return { id, deleted: true, status: UserStatus.INACTIVE };
  }

  private safeUser(user: User) {
    return { id: user.id, username: user.username, role: user.role, status: user.status,
      phone: user.phone, email: user.email, lastLoginAt: user.lastLoginAt, createdAt: user.createdAt };
  }

  async dashboard() {
    const [
      totalPassengers,
      totalDrivers,
      activeDrivers,
      totalTrips,
      completedTrips,
      pendingPayments,
      successfulPayments,
      failedPayments,
      volume,
    ] = await Promise.all([
      this.users.countBy({ role: UserRole.PASSENGER }),
      this.users.countBy({ role: UserRole.DRIVER }),
      this.drivers.countBy({ status: DriverStatus.ACTIVE }),
      this.trips.count(),
      this.trips.countBy({ paymentStatus: PaymentStatus.PAID }),
      this.payments.countBy({ status: PaymentRecordStatus.PENDING }),
      this.payments.countBy({ status: PaymentRecordStatus.SUCCESS }),
      this.payments.countBy({ status: PaymentRecordStatus.FAILED }),
      this.payments
        .createQueryBuilder('payment')
        .select('COALESCE(SUM(payment.amount), 0)', 'total')
        .where('payment.status = :status', { status: PaymentRecordStatus.SUCCESS })
        .getRawOne<{ total: string }>(),
    ]);
    return {
      totalPassengers,
      totalDrivers,
      activeDrivers,
      totalTrips,
      completedTrips,
      pendingPayments,
      successfulPayments,
      failedPayments,
      transactionVolume: Number(volume?.total ?? 0),
      currency: 'ETB',
    };
  }

  async listPayments(limit: number) {
    const rows = await this.payments.find({
      relations: ['passenger', 'driver', 'trip'],
      order: { createdAt: 'DESC' },
      take: limit,
    });
    return rows.map((p) => ({
      id: p.id,
      passengerId: p.passengerId,
      passenger: p.passenger?.username,
      driverId: p.driverId,
      driver: p.driver?.username,
      tripId: p.tripId,
      amount: p.amount,
      currency: p.currency,
      status: p.status,
      createdAt: p.createdAt,
      paidAt: p.completedAt,
      failureReason: p.failureReason,
    }));
  }

  async listTrips(limit: number) {
    const rows = await this.trips.find({
      relations: ['passenger', 'driver'],
      order: { createdAt: 'DESC' },
      take: limit,
    });
    return rows.map((t) => ({
      id: t.id,
      passengerId: t.passengerId,
      passenger: t.passenger?.username,
      driverId: t.driverId,
      driver: t.driver?.username,
      source: t.origin,
      destination: t.destination,
      fareAmount: t.fareAmount,
      currency: t.currency,
      paymentStatus: t.paymentStatus,
      status: t.status,
      createdAt: t.createdAt,
      tariffId: t.tariffId,
      tariffVersion: t.tariffVersion,
    }));
  }

  async listWallets(limit: number) {
    const rows = await this.wallets.find({
      relations: ['user'],
      order: { updatedAt: 'DESC' },
      take: limit,
    });
    return rows.map((w) => ({
      id: w.id,
      ownerId: w.user?.id,
      owner: w.user?.username,
      balance: w.balance,
      currency: w.currency,
      status: w.status,
      updatedAt: w.updatedAt,
    }));
  }
}
