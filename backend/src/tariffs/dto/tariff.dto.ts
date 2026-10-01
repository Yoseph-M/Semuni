import { IsString, IsNotEmpty, IsEnum, IsOptional, IsArray, ValidateNested, IsDateString, IsInt, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty } from '@nestjs/swagger';
import { Currency, VehicleType } from '../../common/enums';

export class CreateTariffRuleDto {
  @ApiProperty({ enum: VehicleType, required: false })
  @IsOptional()
  @IsEnum(VehicleType)
  vehicleType?: VehicleType;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  routeId: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsInt()
  @Min(1)
  startStopSequence?: number;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsInt()
  @Min(1)
  endStopSequence?: number;

  @ApiProperty({ description: 'Base price in minor units (e.g., 8500 santim for 85.00 ETB)' })
  @IsInt()
  @Min(1)
  basePrice: number;
}

export class CreateTariffDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty()
  @IsDateString()
  validFrom: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsDateString()
  validTo?: string;

  @ApiProperty({ enum: Currency, default: Currency.ETB })
  @IsEnum(Currency)
  @IsOptional()
  currency?: Currency;

  @ApiProperty({ type: [CreateTariffRuleDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateTariffRuleDto)
  rules: CreateTariffRuleDto[];
}
