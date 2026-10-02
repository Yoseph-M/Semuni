import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  HttpStatus,
  HttpCode,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiParam } from '@nestjs/swagger';
import { DriversService } from './drivers.service';
import { VehiclesService } from '../vehicles/vehicles.service';
import { WalletsService } from '../wallets/wallets.service';
import { TripsService } from '../trips/trips.service';
import { RoutesService } from '../routes/routes.service';
import { WithdrawalsService } from '../withdrawals/withdrawals.service';
import { PassengersService } from '../passengers/passengers.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { Trip } from '../trips/entities/trip.entity';
import { UserRole, LedgerEntryType } from '../common/enums';
import { RequestWithdrawalDto } from '../withdrawals/dto/withdrawal.dto';

@ApiTags('Drivers')
@Controller('drivers')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class DriversController {
  constructor(
    private readonly driversService: DriversService,
    private readonly vehiclesService: VehiclesService,
    private readonly walletsService: WalletsService,
    private readonly tripsService: TripsService,
    private readonly routesService: RoutesService,
    private readonly withdrawalsService: WithdrawalsService,
    private readonly passengersService: PassengersService,
  ) {}

  @Get('available')
  @Roles(UserRole.PASSENGER)
  @ApiOperation({
    summary:
      'List drivers a passenger may pay (ACTIVE drivers with their minibus). Minimal identity only: a passenger picks the vehicle they are riding in.',
  })
  async findAvailable() {
    const drivers = await this.driversService.findActive();
    const vehicles = await this.vehiclesService.findByDriverIds(
      drivers.map((driver) => driver.userId),
    );
    const plateByDriver = new Map(vehicles.map((vehicle) => [vehicle.driverId, vehicle]));

    return {
      data: drivers.map((driver) => {
        const vehicle = plateByDriver.get(driver.userId);
        return {
          driverUserId: driver.userId,
          fullName: driver.fullName,
          vehiclePlate: vehicle?.plateNumber ?? null,
          vehicleType: vehicle?.vehicleType ?? null,
        };
      }),
      meta: {},
    };
  }

  @Get('me')
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get current driver profile + vehicle info' })
  async getMe(@CurrentUser() user: User) {
    const driver = await this.driversService.findByUserIdOrFail(user.id);
    const vehicle = await this.vehiclesService.findByDriverId(user.id);
    const wallet = await this.walletsService.getWalletByUserId(user.id);
    return {
      data: {
        id: driver.id,
        userId: driver.userId,
        fullName: driver.fullName,
        username: user.username,
        phone: driver.phone,
        licenseNumber: driver.licenseNumber,
        status: driver.status,
        accountBalance: wallet.balance / 100,
        vehiclePlate: vehicle?.plateNumber ?? null,
      },
      meta: {},
    };
  }

  @Get('me/earnings')
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get driver earnings summary (today + total)' })
  async getEarnings(@CurrentUser() user: User) {
    // Earnings are an operational driver surface: a PENDING or SUSPENDED driver
    // may view the profile (GET /drivers/me) but not financial data.
    await this.driversService.assertOperationalDriver(user.id);

    const wallet = await this.walletsService.getWalletByUserId(user.id);
    const trips = await this.tripsService.getDriverTrips(user.id);

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayTrips = trips.filter((t) => t.createdAt >= todayStart);
    const todayEarnings = todayTrips.reduce(
      (sum, t) => sum + (t.paymentStatus === 'PAID' ? t.fareAmount : 0),
      0,
    );
    const totalEarnings = trips.reduce(
      (sum, t) => sum + (t.paymentStatus === 'PAID' ? t.fareAmount : 0),
      0,
    );
    const completedRides = todayTrips.filter((t) => t.paymentStatus === 'PAID').length;
    const avgFare = completedRides > 0 ? Math.round(todayEarnings / completedRides) : 0;

    return {
      data: {
        completedRides,
        totalEarnings: totalEarnings / 100,
        todayEarnings: todayEarnings / 100,
        averageFare: avgFare / 100,
        walletBalance: wallet.balance / 100,
      },
      meta: {},
    };
  }

  @Get('me/transactions')
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get recent driver financial transactions' })
  async getTransactions(@CurrentUser() user: User) {
    await this.driversService.assertOperationalDriver(user.id);

    const entries = await this.walletsService.getWalletTransactions(user.id, 30);
    const trips = await this.tripsService.getDriverTrips(user.id);
    const tripByRef = new Map<string, Trip>();
    for (const t of trips) tripByRef.set(t.id, t);

    const result = [];
    for (const e of entries) {
      const description = e.description || 'Transaction';
      let passengerName = 'System';
      if (e.entryType === LedgerEntryType.DRIVER_EARNING && e.referenceId) {
        const trip = tripByRef.get(e.referenceId);
        if (trip) {
          try {
            const p = await this.passengersService.findByUserId(trip.passengerId);
            if (p) passengerName = p.fullName;
          } catch (_) {}
        }
      } else if (e.entryType === LedgerEntryType.WITHDRAWAL) {
        passengerName = 'Withdrawal';
      }

      result.push({
        id: e.id,
        description,
        amount: e.amount / 100,
        type:
          e.entryType === LedgerEntryType.WITHDRAWAL
            ? 'withdrawal'
            : e.entryType === LedgerEntryType.DRIVER_EARNING
              ? 'payment'
              : 'adjustment',
        createdAt: e.createdAt,
        passengerName,
      });
    }

    return { data: result, meta: {} };
  }

  @Get('me/routes')
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get available / active routes for drivers' })
  async getRoutes() {
    const routes = await this.routesService.findAll();
    return { data: routes, meta: {} };
  }

  @Post('me/withdrawals')
  @Roles(UserRole.DRIVER)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Request a withdrawal from driver wallet' })
  async requestWithdrawal(@CurrentUser() user: User, @Body() dto: RequestWithdrawalDto) {
    const withdrawal = await this.withdrawalsService.requestWithdrawal(user.id, dto);
    return {
      data: withdrawal,
      meta: { message: 'Withdrawal requested successfully' },
    };
  }

  @Get('me/withdrawals')
  @Roles(UserRole.DRIVER)
  @ApiOperation({ summary: 'Get withdrawal history for current driver' })
  async getMyWithdrawals(@CurrentUser() user: User) {
    const withdrawals = await this.withdrawalsService.getMyWithdrawals(user.id);
    return { data: withdrawals, meta: {} };
  }

  @Post('admin/:id/approve')
  @Roles(UserRole.ADMIN)
  @ApiParam({ name: 'id', description: 'Driver ID to approve' })
  @ApiOperation({ summary: 'Approve a pending driver (Admin only)' })
  async approveDriver(@Param('id', ParseUUIDPipe) id: string) {
    const driver = await this.driversService.approve(id);
    return {
      data: { id: driver.id, status: driver.status },
      meta: { message: 'Driver approved successfully' },
    };
  }

  @Post('admin/:id/suspend')
  @Roles(UserRole.ADMIN)
  @ApiParam({ name: 'id', description: 'Driver ID to suspend' })
  @ApiOperation({ summary: 'Suspend an active driver (Admin only)' })
  async suspendDriver(@Param('id', ParseUUIDPipe) id: string) {
    const driver = await this.driversService.suspend(id);
    return {
      data: { id: driver.id, status: driver.status },
      meta: { message: 'Driver suspended successfully' },
    };
  }
}
