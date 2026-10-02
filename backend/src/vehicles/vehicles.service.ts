import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { Vehicle } from './entities/vehicle.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { VehicleStatus, VehicleType } from '../common/enums';

@Injectable()
export class VehiclesService {
  constructor(
    @InjectRepository(Vehicle)
    private readonly vehicleRepository: Repository<Vehicle>,
  ) {}

  async create(vehicleData: Partial<Vehicle>): Promise<Vehicle> {
    const vehicle = this.vehicleRepository.create(vehicleData);
    return this.vehicleRepository.save(vehicle);
  }

  async findById(id: string): Promise<Vehicle | null> {
    return this.vehicleRepository.findOne({ where: { id } });
  }

  async findByDriverId(driverId: string): Promise<Vehicle | null> {
    return this.vehicleRepository.findOne({ where: { driverId } });
  }

  /**
   * Vehicles for many drivers in one query.
   *
   * Exists so a listing (e.g. the passenger-visible driver picker) does not
   * issue one query per driver.
   */
  async findByDriverIds(driverUserIds: string[]): Promise<Vehicle[]> {
    if (driverUserIds.length === 0) return [];
    return this.vehicleRepository.find({
      where: { driverId: In(driverUserIds) },
    });
  }

  async findByIdOrFail(id: string): Promise<Vehicle> {
    const vehicle = await this.findById(id);
    if (!vehicle) {
      throw new DomainException(
        'Vehicle not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.VEHICLE_NOT_FOUND,
      );
    }
    return vehicle;
  }

  /**
   * Authorizes a vehicle for a specific trip.
   *
   * A driver may only operate a vehicle that is (a) theirs and (b) operational;
   * otherwise `driver A` could submit a trip under `driver C`'s minibus. The
   * vehicle may not change type either, because the type selects the tariff rule
   * the fare was quoted from.
   *
   * @param driverUserId the operating driver's **user** id, which is the id the
   *   vehicle is assigned by (`vehicles.driverId` holds a user id).
   */
  async assertUsableByDriver(
    vehicleId: string,
    driverUserId: string,
    expectedType?: VehicleType,
  ): Promise<Vehicle> {
    const vehicle = await this.findByIdOrFail(vehicleId);

    if (vehicle.status !== VehicleStatus.ACTIVE) {
      throw new DomainException(
        `Vehicle is ${vehicle.status.toLowerCase()} and cannot be used for a trip`,
        HttpStatus.BAD_REQUEST,
        ErrorCode.VEHICLE_NOT_ACTIVE,
      );
    }

    if (vehicle.driverId !== driverUserId) {
      throw new DomainException(
        'Vehicle is not assigned to this driver',
        HttpStatus.FORBIDDEN,
        ErrorCode.VEHICLE_NOT_OWNED,
      );
    }

    if (expectedType && vehicle.vehicleType !== expectedType) {
      throw new DomainException(
        `Vehicle type ${vehicle.vehicleType} does not match ${expectedType}`,
        HttpStatus.BAD_REQUEST,
        ErrorCode.VEHICLE_TYPE_MISMATCH,
      );
    }

    return vehicle;
  }

  async assignToDriver(vehicleId: string, driverId: string): Promise<Vehicle> {
    const vehicle = await this.findById(vehicleId);
    if (!vehicle) {
      throw new DomainException(
        'Vehicle not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.VEHICLE_NOT_FOUND,
      );
    }

    vehicle.driverId = driverId;
    return this.vehicleRepository.save(vehicle);
  }
}
