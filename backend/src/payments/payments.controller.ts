import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  Param,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
  ApiResponse,
} from '@nestjs/swagger';
import { PaymentsService } from './payments.service';
import { ProcessTripPaymentDto } from './dto/payment.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { UserRole } from '../common/enums';

@ApiTags('Payments')
@Controller('payments')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('trip')
  @Roles(UserRole.PASSENGER)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Pay for an existing trip (passenger only). Idempotent via idempotencyKey.',
  })
  @ApiResponse({ status: 200, description: 'Payment processed successfully' })
  @ApiResponse({ status: 400, description: 'Trip already paid / invalid' })
  @ApiResponse({ status: 402, description: 'Insufficient wallet balance' })
  async processTripPayment(
    @CurrentUser() user: User,
    @Body() dto: ProcessTripPaymentDto,
  ) {
    const payment = await this.paymentsService.processTripPayment(
      user.id,
      dto,
    );
    return {
      data: {
        paymentId: payment.id,
        tripId: payment.tripId,
        amount: payment.amount,
        currency: payment.currency,
        status: payment.status,
        receiptNumber: payment.receiptNumber,
      },
      meta: { message: 'Payment processed successfully' },
    };
  }

  @Get()
  @ApiOperation({ summary: 'Get payment history for current user' })
  async getMyPayments(@CurrentUser() user: User) {
    const payments = await this.paymentsService.getMyPayments(user.id);
    return { data: payments, meta: {} };
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a specific payment by ID' })
  async getPayment(@Param('id') id: string) {
    const payment = await this.paymentsService.findById(id);
    return { data: payment, meta: {} };
  }
}
