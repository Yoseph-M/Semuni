import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Vehicle } from './entities/vehicle.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

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
