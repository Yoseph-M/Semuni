import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Payment } from './entities/payment.entity';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { Wallet } from '../wallets/entities/wallet.entity';
import { Trip } from '../trips/entities/trip.entity';
import { WalletsService } from '../wallets/wallets.service';
import { LedgerService } from '../ledger/ledger.service';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { TripsService } from '../trips/trips.service';
import { DriversService } from '../drivers/drivers.service';
import { NotificationsService } from '../notifications/notifications.service';
import { Driver } from '../drivers/entities/driver.entity';
import { CustomLogger } from '../common/logger/custom.logger';
import { FaresModule } from '../fares/fares.module';
import { VehiclesModule } from '../vehicles/vehicles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Payment, Wallet, Trip, Driver, LedgerEntry]),
    // TripsService (re-provided below) recalculates fares server-side and
    // checks vehicle ownership.
    FaresModule,
    VehiclesModule,
  ],
  providers: [
    PaymentsService,
    WalletsService,
    LedgerService,
    TripsService,
    DriversService,
    NotificationsService,
    CustomLogger,
  ],
  controllers: [PaymentsController],
  exports: [PaymentsService],
})
export class PaymentsModule {}
