import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  Param,
  ParseUUIDPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TripsService } from './trips.service';
import { CreateTripDto } from './dto/trip.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';
import { UserRole } from '../common/enums';
import { Driver } from '../drivers/entities/driver.entity';
import { Passenger } from '../passengers/entities/passenger.entity';
import { PassengersService } from '../passengers/passengers.service';
import { DriversService } from '../drivers/drivers.service';

@ApiTags('Trips')
@Controller('trips')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
export class TripsController {
  constructor(
    private readonly tripsService: TripsService,
    private readonly passengersService: PassengersService,
    private readonly driversService: DriversService,
    @InjectRepository(Driver)
    private readonly driverRepo: Repository<Driver>,
    @InjectRepository(Passenger)
    private readonly passengerRepo: Repository<Passenger>,
  ) {}

  @Post()
  @Roles(UserRole.PASSENGER)
  @ApiOperation({
    summary:
      'Create a new trip record (passenger only). Fare is stored as provided from fare calculation.',
  })
  async createTrip(@CurrentUser() user: User, @Body() dto: CreateTripDto) {
    await this.passengersService.findByUserIdOrFail(user.id);
    const trip = await this.tripsService.createTrip(user.id, dto);
    return { data: trip, meta: { message: 'Trip created successfully' } };
  }

  @Get()
  @ApiOperation({ summary: 'Get trips for current user' })
  async getMyTrips(@CurrentUser() user: User) {
    const trips = await this.tripsService.getMyTrips(user.id);
    const enriched = [];
    for (const t of trips) {
      const isPassenger = t.passengerId === user.id;
      const otherUserId = isPassenger ? t.driverId : t.passengerId;
      let otherName = 'Unknown';
      try {
        if (isPassenger) {
          const d = await this.driverRepo.findOne({
            where: { userId: otherUserId },
          });
          if (d) otherName = d.fullName;
        } else {
          const p = await this.passengerRepo.findOne({
            where: { userId: otherUserId },
          });
          if (p) otherName = p.fullName;
        }
      } catch (_) {}
      enriched.push({
        ...t,
        driverName: isPassenger ? otherName : undefined,
        passengerName: !isPassenger ? otherName : undefined,
        amountPaid: t.fareAmount / 100,
      });
    }
    return { data: enriched, meta: {} };
  }

  @Get(':id')
  @ApiOperation({
    summary:
      'Get a specific trip by ID. Passengers may read only their own trips, drivers only trips assigned to them; ADMIN has privileged access.',
  })
  async getTrip(
    @CurrentUser() user: User,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    // Object-level authorization lives in the service, so it applies however
    // the trip is reached — not just through this route.
    const trip = await this.tripsService.findByIdForUser(id, user);
    return { data: trip, meta: {} };
  }
}
