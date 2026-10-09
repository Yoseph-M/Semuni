import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
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
  @ApiOperation({ summary: 'Get the tariff that currently prices new fares' })
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

  @Get(':id')
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Get a tariff version by ID (Admin only)' })
  async findOne(@Param('id', ParseUUIDPipe) id: string) {
    const tariff = await this.tariffsService.findById(id);
    return { data: tariff, meta: {} };
  }

  @Post()
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary:
      'Create a tariff version in DRAFT (Admin only). Creating a tariff never makes it live.',
  })
  async create(@Body() dto: CreateTariffDto) {
    const tariff = await this.tariffsService.create(dto);
    return { data: tariff, meta: { message: 'Tariff created in DRAFT' } };
  }

  @Post(':id/activate')
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary:
      'Activate a DRAFT tariff (Admin only). Only one tariff may be active at a time.',
  })
  async activate(@Param('id', ParseUUIDPipe) id: string) {
    const tariff = await this.tariffsService.activate(id);
    return { data: tariff, meta: { message: 'Tariff activated' } };
  }

  @Post(':id/expire')
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary:
      'Expire a DRAFT or ACTIVE tariff (Admin only). Expiring frees the active slot.',
  })
  async expire(@Param('id', ParseUUIDPipe) id: string) {
    const tariff = await this.tariffsService.expire(id);
    return { data: tariff, meta: { message: 'Tariff expired' } };
  }
}
