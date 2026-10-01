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

    const stops = dto.stops ?? [];
    if (stops.length < 2) {
      throw new DomainException(
        'A route must contain at least an origin and destination stop',
        HttpStatus.BAD_REQUEST,
        ErrorCode.STOP_ORDER_INVALID,
      );
    }

    const sequences = stops.map((stop) => stop.sequence);
    if (
      sequences.some((sequence) => !Number.isInteger(sequence) || sequence <= 0) ||
      new Set(sequences).size !== sequences.length
    ) {
      throw new DomainException(
        'Route stop sequences must be unique positive integers',
        HttpStatus.BAD_REQUEST,
        ErrorCode.STOP_ORDER_INVALID,
      );
    }

    const orderedStops = [...stops].sort((a, b) => a.sequence - b.sequence);
    const normalize = (value: string) => value.trim().toLowerCase();
    if (
      normalize(orderedStops[0].name) !== normalize(dto.origin) ||
      normalize(orderedStops[orderedStops.length - 1].name) !== normalize(dto.destination)
    ) {
      throw new DomainException(
        'Route origin/destination must match the first and last stop',
        HttpStatus.BAD_REQUEST,
        ErrorCode.STOP_ORDER_INVALID,
      );
    }

    const route = this.routeRepository.create({
      name: dto.name,
      origin: orderedStops[0].name,
      destination: orderedStops[orderedStops.length - 1].name,
      code: dto.code,
      stops: orderedStops,
    });
    return this.routeRepository.save(route);
  }

  async findAll(): Promise<Route[]> {
    return this.routeRepository.find({ relations: ['stops'] });
  }

  async findById(id: string, options?: { requireActive?: boolean }): Promise<Route> {
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
