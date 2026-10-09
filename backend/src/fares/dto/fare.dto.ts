import { IsUUID, IsEnum, IsOptional } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { VehicleType } from '../../common/enums';

export class CalculateFareDto {
  @ApiProperty({ description: 'Route UUID' })
  @IsUUID()
  routeId: string;

  @ApiProperty({ description: 'Origin RouteStop UUID' })
  @IsUUID()
  originStopId: string;

  @ApiProperty({ description: 'Destination RouteStop UUID' })
  @IsUUID()
  destinationStopId: string;

  @ApiProperty({ enum: VehicleType, default: VehicleType.MINIBUS, required: false })
  @IsOptional()
  @IsEnum(VehicleType)
  vehicleType?: VehicleType;
}
