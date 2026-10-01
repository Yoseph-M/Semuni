import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { Driver } from './entities/driver.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { DriverStatus } from '../common/enums';
import { User } from '../users/entities/user.entity';

@Injectable()
export class DriversService {
  constructor(
    @InjectRepository(Driver)
    private readonly driverRepository: Repository<Driver>,
  ) {}

  async create(
    user: User,
    fullName: string,
    licenseNumber: string,
    manager?: EntityManager,
  ): Promise<Driver> {
    const repo = manager
      ? manager.getRepository(Driver)
      : this.driverRepository;
    const driver = repo.create({
      user,
      userId: user.id,
      fullName,
      phone: user.phone,
      licenseNumber,
    });
    return repo.save(driver);
  }

  async findByUserId(userId: string): Promise<Driver | null> {
    return this.driverRepository.findOne({ where: { userId } });
  }

  async findByUserIdOrFail(userId: string): Promise<Driver> {
    const driver = await this.findByUserId(userId);
    if (!driver) {
      throw new DomainException(
        'Driver not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.DRIVER_NOT_FOUND,
      );
    }
    return driver;
  }

  async findByIdOrFail(id: string): Promise<Driver> {
    const driver = await this.driverRepository.findOne({ where: { id } });
    if (!driver) {
      throw new DomainException(
        'Driver not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.DRIVER_NOT_FOUND,
      );
    }
    return driver;
  }

  /**
   * The operational-driver policy: `user.status = ACTIVE` (enforced on every
   * request by JwtStrategy) **and** `driver.status = ACTIVE` (enforced here).
   *
   * A driver whose application is still PENDING or has been SUSPENDED must not
   * gain financial or transport privileges just because the user account exists.
   * Profile reads stay available so the app can display the status.
   */
  async assertOperationalDriver(userId: string): Promise<Driver> {
    const driver = await this.findByUserIdOrFail(userId);
    if (driver.status !== DriverStatus.ACTIVE) {
      throw new DomainException(
        `Driver account is ${driver.status.toLowerCase()}`,
        HttpStatus.FORBIDDEN,
        ErrorCode.DRIVER_NOT_ACTIVE,
      );
    }
    return driver;
  }

  async approve(driverId: string): Promise<Driver> {
    const driver = await this.findByIdOrFail(driverId);
    driver.status = DriverStatus.ACTIVE;
    return this.driverRepository.save(driver);
  }

  async suspend(driverId: string): Promise<Driver> {
    const driver = await this.findByIdOrFail(driverId);
    driver.status = DriverStatus.SUSPENDED;
    return this.driverRepository.save(driver);
  }
}
