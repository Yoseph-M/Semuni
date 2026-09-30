import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { Trip } from './entities/trip.entity';
import { CreateTripDto } from './dto/trip.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { TripStatus, PaymentStatus, Currency, DriverStatus } from '../common/enums';
import { DriversService } from '../drivers/drivers.service';
import { FaresService } from '../fares/fares.service';

@Injectable()
export class TripsService {
  constructor(
    @InjectRepository(Trip)
    private readonly tripRepository: Repository<Trip>,
    private readonly driversService: DriversService,
    private readonly faresService: FaresService,
  ) {}

  async createTrip(passengerUserId: string, dto: CreateTripDto): Promise<Trip> {
    const driver = await this.driversService.findByUserIdOrFail(dto.driverId);
    if (driver.status !== DriverStatus.ACTIVE) {
      throw new DomainException(
        'Driver is not active',
        HttpStatus.BAD_REQUEST,
        ErrorCode.DRIVER_NOT_ACTIVE,
      );
    }

    // The server — never the client — decides the fare. It is recalculated from
    // the active tariff here and the trip stores this authoritative quote, so a
    // tampered or stale client value can never be paid. Route and tariff
    // identifiers are taken from the quote for the same reason.
    const quote = await this.faresService.calculateFare({
      origin: dto.origin,
      destination: dto.destination,
      vehicleType: dto.vehicleType,
    });

    // A client-quoted fare is tolerated only if it agrees. Disagreement means a
    // stale tariff on the client or tampering, and either way it fails loudly.
    if (dto.fareAmount !== undefined && dto.fareAmount !== quote.fare) {
      throw new DomainException(
        `Quoted fare ${dto.fareAmount} does not match the official fare ${quote.fare} for this route`,
        HttpStatus.BAD_REQUEST,
        ErrorCode.FARE_MISMATCH,
      );
    }

    const trip = this.tripRepository.create({
      passengerId: passengerUserId,
      driverId: dto.driverId,
      vehicleId: dto.vehicleId,
      routeId: quote.routeId,
      origin: dto.origin,
      destination: dto.destination,
      fareAmount: quote.fare,
      currency: quote.currency as Currency,
      tariffId: quote.tariffId,
      tariffRuleId: quote.tariffRuleId,
      tariffVersion: quote.tariffVersion,
      status: TripStatus.PENDING,
      paymentStatus: PaymentStatus.UNPAID,
      startedAt: new Date(),
    });

    return this.tripRepository.save(trip);
  }

  async findById(tripId: string): Promise<Trip> {
    const trip = await this.tripRepository.findOne({ where: { id: tripId } });
    if (!trip) {
      throw new DomainException(
        'Trip not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TRIP_NOT_FOUND,
      );
    }
    return trip;
  }

  async markPaid(
    manager: EntityManager,
    tripId: string,
    paymentId: string,
  ): Promise<void> {
    await manager.update(
      Trip,
      { id: tripId },
      {
        paymentStatus: PaymentStatus.PAID,
        status: TripStatus.COMPLETED,
        paymentId,
        completedAt: new Date(),
      },
    );
  }

  async getMyTrips(userId: string): Promise<Trip[]> {
    return this.tripRepository.find({
      where: [{ passengerId: userId }, { driverId: userId }],
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  async getPassengerTrips(passengerUserId: string): Promise<Trip[]> {
    return this.tripRepository.find({
      where: { passengerId: passengerUserId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }

  async getDriverTrips(driverUserId: string): Promise<Trip[]> {
    return this.tripRepository.find({
      where: { driverId: driverUserId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }
}
