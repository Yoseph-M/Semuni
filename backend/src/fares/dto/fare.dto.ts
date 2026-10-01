import { IsUUID, IsEnum, IsOptional } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { VehicleType } from '../../common/enums';

export class CalculateFareDto {
  @ApiProperty({ example: 'Bole', description: 'Origin location / stop name' })
  @IsString()
  @IsNotEmpty()
  origin: string;

  @ApiProperty({ example: 'Piazza', description: 'Destination location / stop name' })
  @IsString()
  @IsNotEmpty()
  destination: string;

  @ApiProperty({ enum: VehicleType, default: VehicleType.MINIBUS, required: false })
  @IsOptional()
  @IsEnum(VehicleType)
  vehicleType?: VehicleType;
}
