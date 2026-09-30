import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThanOrEqual, IsNull, MoreThanOrEqual } from 'typeorm';
import { Tariff } from './entities/tariff.entity';
import { CreateTariffDto } from './dto/tariff.dto';
import { RoutesService } from '../routes/routes.service';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

@Injectable()
export class TariffsService {
  constructor(
    @InjectRepository(Tariff)
    private readonly tariffRepository: Repository<Tariff>,
    private readonly routesService: RoutesService,
  ) {}

  async create(dto: CreateTariffDto): Promise<Tariff> {
    // Validate that all routes referenced in the rules exist
    for (const rule of dto.rules) {
      await this.routesService.findById(rule.routeId);
    }

    const tariff = this.tariffRepository.create({
      name: dto.name,
      validFrom: new Date(dto.validFrom),
      validTo: dto.validTo ? new Date(dto.validTo) : undefined,
      currency: dto.currency,
      rules: dto.rules.map(rule => ({
        route: { id: rule.routeId },
        vehicleType: rule.vehicleType,
        startStopSequence: rule.startStopSequence,
        endStopSequence: rule.endStopSequence,
        basePrice: rule.basePrice,
      })),
    });

    return this.tariffRepository.save(tariff);
  }

  async findAll(): Promise<Tariff[]> {
    return this.tariffRepository.find({ relations: ['rules', 'rules.route'] });
  }

  async getActiveTariff(): Promise<Tariff> {
    const now = new Date();
    const tariff = await this.tariffRepository.findOne({
      where: [
        {
          validFrom: LessThanOrEqual(now),
          validTo: IsNull(),
        },
        {
          validFrom: LessThanOrEqual(now),
          validTo: MoreThanOrEqual(now),
        },
      ],
      order: {
        validFrom: 'DESC',
      },
      relations: ['rules', 'rules.route'],
    });

    if (!tariff) {
      throw new DomainException(
        'No active tariff found',
        HttpStatus.NOT_FOUND,
        ErrorCode.TARIFF_NOT_FOUND,
      );
    }
    return tariff;
  }
}
