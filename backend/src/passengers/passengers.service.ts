import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { Passenger } from './entities/passenger.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { User } from '../users/entities/user.entity';

@Injectable()
export class PassengersService {
  constructor(
    @InjectRepository(Passenger)
    private readonly passengerRepository: Repository<Passenger>,
  ) {}

  async create(
    user: User,
    fullName: string,
    manager?: EntityManager,
  ): Promise<Passenger> {
    const repo = manager
      ? manager.getRepository(Passenger)
      : this.passengerRepository;
    const passenger = repo.create({
      user,
      userId: user.id,
      fullName,
      phone: user.phone,
    });
    return repo.save(passenger);
  }

  async findByUserId(userId: string): Promise<Passenger | null> {
    return this.passengerRepository.findOne({ where: { userId } });
  }

  async findByUserIdOrFail(userId: string): Promise<Passenger> {
    const passenger = await this.findByUserId(userId);
    if (!passenger) {
      throw new DomainException(
        'Passenger not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.PASSENGER_NOT_FOUND,
      );
    }
    return passenger;
  }
}
