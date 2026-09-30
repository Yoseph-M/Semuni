import { Controller, Post, Body, Get, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse } from '@nestjs/swagger';
import { WithdrawalsService } from './withdrawals.service';
import { RequestWithdrawalDto } from './dto/withdrawal.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';

@ApiTags('Withdrawals')
@Controller('withdrawals')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard)
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
