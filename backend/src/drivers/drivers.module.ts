import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Driver } from './entities/driver.entity';
import { DriversService } from './drivers.service';
import { DriversController } from './drivers.controller';
import { Vehicle } from '../vehicles/entities/vehicle.entity';
import { Wallet } from '../wallets/entities/wallet.entity';
import { Trip } from '../trips/entities/trip.entity';
import { Route } from '../routes/entities/route.entity';
import { Withdrawal } from '../withdrawals/entities/withdrawal.entity';
import { Passenger } from '../passengers/entities/passenger.entity';
import { LedgerEntry } from '../ledger/entities/ledger-entry.entity';
import { WalletsService } from '../wallets/wallets.service';
import { LedgerService } from '../ledger/ledger.service';
import { TripsService } from '../trips/trips.service';
import { RoutesService } from '../routes/routes.service';
import { VehiclesService } from '../vehicles/vehicles.service';
import { WithdrawalsService } from '../withdrawals/withdrawals.service';
import { PassengersService } from '../passengers/passengers.service';
import { FaresModule } from '../fares/fares.module';
import { VehiclesModule } from '../vehicles/vehicles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Driver,
      Vehicle,
      Wallet,
      Trip,
      Route,
      Withdrawal,
      Passenger,
      LedgerEntry,
    ]),
    // TripsService (re-provided below) recalculates fares server-side and
    // checks vehicle ownership.
    FaresModule,
    VehiclesModule,
  ],
  providers: [
    DriversService,
    VehiclesService,
    WalletsService,
    LedgerService,
    TripsService,
    RoutesService,
    WithdrawalsService,
    PassengersService,
  ],
  controllers: [DriversController],
  exports: [DriversService, TypeOrmModule],
})
export class DriversModule {}
