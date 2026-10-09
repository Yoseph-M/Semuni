import {
  Controller,
  Get,
  UseGuards,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { PassengersService } from './passengers.service';
import { DriversService } from '../drivers/drivers.service';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { UserRole } from '../common/enums';

@ApiTags('Passengers')
@Controller('passengers')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class PassengersController {
  constructor(
    private readonly passengersService: PassengersService,
    private readonly driversService: DriversService,
    private readonly walletsService: WalletsService,
    private readonly tripsService: TripsService,
  ) {}

  @Get('me')
  @Roles(UserRole.PASSENGER)
  @ApiOperation({ summary: 'Get current passenger profile + wallet summary' })
  async getMe(@CurrentUser() user: User) {
    const passenger = await this.passengersService.findByUserIdOrFail(user.id);
    const wallet = await this.walletsService.getWalletByUserId(user.id);
    return {
      data: {
        id: passenger.id,
        userId: passenger.userId,
        fullName: passenger.fullName,
        username: user.username,
        phone: passenger.phone,
        wallet: {
          balance: wallet.balance,
          currency: wallet.currency,
        },
      },
      meta: {},
    };
  }

  @Get('me/trips')
  @Roles(UserRole.PASSENGER)
  @ApiOperation({ summary: 'Get trip history for current passenger' })
  async getMyTrips(@CurrentUser() user: User) {
    const trips = await this.tripsService.getPassengerTrips(user.id);
    const enriched = await Promise.all(
      trips.map(async (t) => {
        let driverName = 'Unknown';
        try {
          const d = await this.driversService.findByUserId(t.driverId);
          if (d) driverName = d.fullName;
        } catch (_) {}
        return {
          ...t,
          driverName,
        };
      }),
    );
    return { data: enriched, meta: {} };
  }
}
