import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Param,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { RoutesService } from './routes.service';
import { CreateRouteDto, UpdateRouteDto } from './dto/route.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '../common/enums';

@ApiTags('Routes')
@Controller('routes')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class RoutesController {
  constructor(private readonly routesService: RoutesService) {}

  @Get()
  @ApiOperation({ summary: 'Get all active routes (accessible to all roles)' })
  async findAll() {
    const routes = await this.routesService.findAll();
    return { data: routes, meta: {} };
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a specific route by ID' })
  async findOne(@Param('id', ParseUUIDPipe) id: string) {
    const route = await this.routesService.findById(id);
    return { data: route, meta: {} };
  }

  @Post()
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Create a new route (Admin only)' })
  async create(@Body() dto: CreateRouteDto) {
    const route = await this.routesService.create(dto);
    return { data: route, meta: { message: 'Route created successfully' } };
  }

  @Patch(':id')
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Update route status (Admin only)' })
  async update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateRouteDto) {
    const route = await this.routesService.update(id, dto);
    return { data: route, meta: { message: 'Route updated successfully' } };
  }
}
