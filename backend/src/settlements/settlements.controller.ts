import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { SettlementsService } from './settlements.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '../common/enums';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';

@ApiTags('Settlements')
@Controller('settlements')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class SettlementsController {
  constructor(private readonly settlementsService: SettlementsService) {}

  @Get()
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get settlement history for current driver' })
  async getMySettlements(@CurrentUser() user: User) {
    const settlements = await this.settlementsService.getMySettlements(user.id);
    return { data: settlements, meta: {} };
  }

  @Post('process')
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Batch process pending withdrawals into settlements (Admin only)' })
  async processPendingWithdrawals() {
    const result = await this.settlementsService.processPendingWithdrawals();
    return { data: result, meta: {} };
  }
}
