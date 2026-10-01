import {
  IsString,
  IsNotEmpty,
  IsUUID,
  IsOptional,
  IsEnum,
  IsNumber,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { VehicleType } from '../../common/enums';

export class CreateTripDto {
  @ApiProperty({ description: 'Driver ID for this trip' })
  @IsUUID()
  @IsNotEmpty()
  driverId: string;

  @ApiProperty({ description: 'Vehicle ID (optional)' })
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiProperty({ description: 'Route UUID' })
  @IsUUID()
  routeId: string;

  @ApiProperty({ description: 'Origin RouteStop UUID' })
  @IsUUID()
  originStopId: string;

  @ApiProperty({ description: 'Destination RouteStop UUID' })
  @IsUUID()
  destinationStopId: string;

  @ApiProperty({ description: 'Origin location / stop name' })
  @IsString()
  @IsNotEmpty()
  origin: string;

  @ApiProperty({ description: 'Destination location / stop name' })
  @IsString()
  @IsNotEmpty()
  destination: string;

  @ApiProperty({ description: 'Tariff ID from fare calculation' })
  @IsOptional()
  @IsUUID()
  tariffId?: string;

  @ApiProperty({ description: 'Tariff rule ID from fare calculation (optional)' })
  @IsOptional()
  @IsUUID()
  tariffRuleId?: string;

  @ApiProperty({ description: 'Tariff version label (optional)' })
  @IsOptional()
  @IsString()
  tariffVersion?: string;

  @ApiProperty({
    enum: VehicleType,
    default: VehicleType.MINIBUS,
    required: false,
    description:
      'Vehicle type used to resolve the applicable tariff rule server-side.',
  })
  @IsOptional()
  @IsEnum(VehicleType)
  vehicleType?: VehicleType;

  @ApiProperty({
    description:
      'OPTIONAL and never trusted: the fare the client calculated. If supplied it must equal the server-calculated official fare, otherwise the trip is rejected with FARE_MISMATCH. The stored fare always comes from the active tariff.',
    required: false,
  })
  @IsOptional()
  @IsNumber()
  fareAmount?: number;
}
