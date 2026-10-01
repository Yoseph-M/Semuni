import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { Trip } from './entities/trip.entity';
import { CreateTripDto } from './dto/trip.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { TripStatus, PaymentStatus, Currency, DriverStatus, UserRole } from '../common/enums';
import { DriversService } from '../drivers/drivers.service';
import { FaresService } from '../fares/fares.service';
import { VehiclesService } from '../vehicles/vehicles.service';

@Injectable()
export class TripsService {
  constructor(
    @InjectRepository(Trip)
    private readonly tripRepository: Repository<Trip>,
    private readonly driversService: DriversService,
    private readonly faresService: FaresService,
    private readonly vehiclesService: VehiclesService,
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

    // A trip may only use a vehicle that belongs to the driver operating it and
    // that is fit to drive. Checked before the fare quote so a mismatched
    // vehicle is rejected without needing any tariff data.
    const vehicle = dto.vehicleId
      ? await this.vehiclesService.assertUsableByDriver(
          dto.vehicleId,
          driver.userId,
          dto.vehicleType,
        )
      : undefined;

    // The server — never the client — decides the fare. It is recalculated from
    // the active tariff here and the trip stores this authoritative quote, so a
    // tampered or stale client value can never be paid. Route and tariff
    // identifiers are taken from the quote for the same reason.
    const quote = await this.faresService.calculateFare({
      origin: dto.origin,
      destination: dto.destination,
      // When the client does not state a vehicle type, the quoted one is the
      // type of the vehicle actually operating the trip.
      vehicleType: dto.vehicleType ?? vehicle?.vehicleType,
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
      vehicleId: vehicle?.id ?? dto.vehicleId,
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

  /**
   * Loads a trip only for a caller entitled to see it.
   *
   * Authorization policy, applied consistently across the API:
   *   - the owning passenger and the assigned driver may read the trip
   *   - ADMIN has an explicit privileged branch (the /admin namespace comes later)
   *   - any other authenticated user gets 403 TRIP_NOT_OWNED
   *   - an unknown id gets 404 — a malformed or foreign UUID is never useful
   *
   * Authentication is not authorization: a valid token must not grant access to
   * an arbitrary trip.
   */
  async findByIdForUser(
    tripId: string,
    user: { id: string; role: UserRole },
  ): Promise<Trip> {
    const trip = await this.findById(tripId);

    const isParticipant =
      trip.passengerId === user.id || trip.driverId === user.id;
    if (!isParticipant && user.role !== UserRole.ADMIN) {
      throw new DomainException(
        'Trip does not belong to this user',
        HttpStatus.FORBIDDEN,
        ErrorCode.TRIP_NOT_OWNED,
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
