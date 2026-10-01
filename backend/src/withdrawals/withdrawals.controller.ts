import { Controller, Post, Body, Get, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse } from '@nestjs/swagger';
import { WithdrawalsService } from './withdrawals.service';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { UserRole } from '../common/enums';

@ApiTags('Withdrawals')
@Controller('withdrawals')
@ApiBearerAuth('access-token')
// Drivers only — and WithdrawalsService re-verifies the driver profile and its
// ACTIVE status, because a role decorator alone is not an authorization policy.
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.DRIVER)
export class WithdrawalsController {
  constructor(private readonly withdrawalsService: WithdrawalsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Request a withdrawal from wallet' })
  @ApiResponse({ status: 201, description: 'Withdrawal requested' })
  async requestWithdrawal(@CurrentUser() user: User, @Body() dto: RequestWithdrawalDto) {
    const withdrawal = await this.withdrawalsService.requestWithdrawal(user.id, dto);
    return { data: withdrawal, meta: { message: 'Withdrawal requested successfully' } };
  }

  @Get()
  @ApiOperation({ summary: 'Get withdrawal history for current user' })
  async getMyWithdrawals(@CurrentUser() user: User) {
    const withdrawals = await this.withdrawalsService.getMyWithdrawals(user.id);
    return { data: withdrawals, meta: {} };
  }
}
