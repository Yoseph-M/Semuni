import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Passenger } from './entities/passenger.entity';
import { PassengersService } from './passengers.service';
import { PassengersController } from './passengers.controller';
import { Trip } from '../trips/entities/trip.entity';
import { Driver } from '../drivers/entities/driver.entity';
import { Wallet } from '../wallets/entities/wallet.entity';
import { WalletsService } from '../wallets/wallets.service';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { LedgerService } from '../ledger/ledger.service';
import { TripsService } from '../trips/trips.service';
import { DriversService } from '../drivers/drivers.service';
import { FaresModule } from '../fares/fares.module';
import { VehiclesModule } from '../vehicles/vehicles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Passenger, Trip, Driver, Wallet, LedgerEntry]),
    // TripsService (re-provided below) recalculates fares server-side and
    // checks vehicle ownership.
    FaresModule,
    VehiclesModule,
  ],
  providers: [
    PassengersService,
    WalletsService,
    LedgerService,
    TripsService,
    DriversService,
  ],
  controllers: [PassengersController],
  exports: [PassengersService, TypeOrmModule],
})
export class PassengersModule {}
