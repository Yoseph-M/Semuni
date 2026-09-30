import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { User } from './entities/user.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import * as bcrypt from 'bcrypt';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
  ) {}

  async findByUsername(username: string): Promise<User | null> {
    return this.userRepository.findOne({ where: { username } });
  }

  async findByPhone(phone: string): Promise<User | null> {
    return this.userRepository.findOne({ where: { phone } });
  }

  async findById(id: string): Promise<User | null> {
    return this.userRepository.findOne({ where: { id } });
  }

  /**
   * Creates a user.
   *
   * Pass [manager] to participate in an ambient transaction so the user row and
   * any related profile rows commit or roll back together.
   */
  async create(
    userData: Partial<User>,
    manager?: EntityManager,
  ): Promise<User> {
    const repo = manager ? manager.getRepository(User) : this.userRepository;

    const existing = await repo.findOne({
      where: { username: userData.username! },
    });
    if (existing) {
      throw new DomainException(
        'User with this username already exists',
        HttpStatus.CONFLICT,
        ErrorCode.AUTH_USER_EXISTS,
      );
    }

    // Phone is optional but still unique, so guard against a raw 500.
    if (userData.phone) {
      const phoneTaken = await repo.findOne({
        where: { phone: userData.phone },
      });
      if (phoneTaken) {
        throw new DomainException(
          'User with this phone number already exists',
          HttpStatus.CONFLICT,
          ErrorCode.AUTH_USER_EXISTS,
        );
      }
    }

    if (userData.passwordHash) {
      userData.passwordHash = await bcrypt.hash(userData.passwordHash, 10);
    }

    const user = repo.create(userData);
    return repo.save(user);
  }

  async updateLastLogin(id: string): Promise<void> {
    await this.userRepository.update(id, { lastLoginAt: new Date() });
  }
}
