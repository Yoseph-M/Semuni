import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards, ParseUUIDPipe } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '../common/enums';
import { AdminService } from './admin.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { CreateAdminUserDto, UpdateAdminUserDto } from './dto/admin-user.dto';

@ApiTags('Admin')
@ApiBearerAuth('access-token')
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('dashboard')
  @ApiOperation({ summary: 'Operational dashboard (Admin only)' })
  async dashboard() {
    return { data: await this.admin.dashboard(), meta: {} };
  }

  @Get('payments')
  @ApiOperation({ summary: 'Recent payment monitoring records (Admin only)' })
  async payments(@Query('limit') limit?: string) {
    return { data: await this.admin.listPayments(pageSize(limit)), meta: {} };
  }

  @Get('trips')
  @ApiOperation({ summary: 'Recent trip monitoring records (Admin only)' })
  async trips(@Query('limit') limit?: string) {
    return { data: await this.admin.listTrips(pageSize(limit)), meta: {} };
  }

  @Get('wallets')
  @ApiOperation({ summary: 'Wallet balances for operational visibility (Admin only)' })
  async wallets(@Query('limit') limit?: string) {
    return { data: await this.admin.listWallets(pageSize(limit)), meta: {} };
  }

  @Get('users')
  async users() { return { data: await this.admin.listUsers(), meta: {} }; }

  @Post('users')
  async createUser(@Body() dto: CreateAdminUserDto) {
    return { data: await this.admin.createUser(dto), meta: { message: 'User created' } };
  }

  @Patch('users/:id')
  async updateUser(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateAdminUserDto) {
    return { data: await this.admin.updateUser(id, dto), meta: { message: 'User updated' } };
  }

  @Delete('users/:id')
  async deleteUser(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() actor: User) {
    return { data: await this.admin.removeUser(id, actor.id), meta: { message: 'User deleted' } };
  }
}

function pageSize(value?: string): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, 100) : 50;
}
