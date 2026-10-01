import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Trip } from './entities/trip.entity';
import { TripsService } from './trips.service';
import { TripsController } from './trips.controller';
import { Driver } from '../drivers/entities/driver.entity';
import { Passenger } from '../passengers/entities/passenger.entity';
import { DriversModule } from '../drivers/drivers.module';
import { PassengersModule } from '../passengers/passengers.module';
import { UsersModule } from '../users/users.module';
import { FaresModule } from '../fares/fares.module';
import { VehiclesModule } from '../vehicles/vehicles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Trip, Driver, Passenger]),
    forwardRef(() => DriversModule),
    forwardRef(() => PassengersModule),
    UsersModule,
    // TripsService recalculates the official fare rather than trusting the client.
    FaresModule,
    // ...and verifies the vehicle belongs to the operating driver.
    VehiclesModule,
  ],
  providers: [TripsService],
  controllers: [TripsController],
  exports: [TripsService, TypeOrmModule],
})
export class TripsModule {}
