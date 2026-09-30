import { Controller, Get, Post, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { TariffsService } from './tariffs.service';
import { CreateTariffDto } from './dto/tariff.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '../common/enums';

@ApiTags('Tariffs')
@Controller('tariffs')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class TariffsController {
  constructor(private readonly tariffsService: TariffsService) {}

  @Get('active')
  @ApiOperation({ summary: 'Get current active tariff' })
  async getActiveTariff() {
    const tariff = await this.tariffsService.getActiveTariff();
    return { data: tariff, meta: {} };
  }

  @Get()
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Get all tariffs (Admin only)' })
  async findAll() {
    const tariffs = await this.tariffsService.findAll();
    return { data: tariffs, meta: {} };
  }

  @Post()
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Create a new tariff (Admin only)' })
  async create(@Body() dto: CreateTariffDto) {
    const tariff = await this.tariffsService.create(dto);
    return { data: tariff, meta: { message: 'Tariff created successfully' } };
  }
}
