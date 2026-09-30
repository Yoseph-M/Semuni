import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Route } from './entities/route.entity';
import { CreateRouteDto, UpdateRouteDto } from './dto/route.dto';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

@Injectable()
export class RoutesService {
  constructor(
    @InjectRepository(Route)
    private readonly routeRepository: Repository<Route>,
  ) {}

  async create(dto: CreateRouteDto): Promise<Route> {
    const existing = await this.routeRepository.findOne({ where: { code: dto.code } });
    if (existing) {
      throw new DomainException(
        'Route with this code already exists',
        HttpStatus.CONFLICT,
        ErrorCode.VALIDATION_ERROR,
      );
    }

    const route = this.routeRepository.create(dto);
    return this.routeRepository.save(route);
  }

  async findAll(): Promise<Route[]> {
    return this.routeRepository.find({ relations: ['stops'] });
  }

  async findById(id: string): Promise<Route> {
    const route = await this.routeRepository.findOne({ 
      where: { id },
      relations: ['stops'],
    });
    
    if (!route) {
      throw new DomainException(
        'Route not found',
        HttpStatus.NOT_FOUND,
        ErrorCode.ROUTE_NOT_FOUND,
      );
    }
    return route;
  }

  async update(id: string, dto: UpdateRouteDto): Promise<Route> {
    const route = await this.findById(id);
    route.status = dto.status;
    return this.routeRepository.save(route);
  }
}
