import { IsString, IsNotEmpty, IsEnum, IsOptional, IsArray, ValidateNested, IsNumber } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty } from '@nestjs/swagger';
import { RouteStatus } from '../../common/enums';

export class CreateRouteStopDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty()
  @IsNumber()
  sequence: number;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsNumber()
  latitude?: number;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsNumber()
  longitude?: number;
}

export class CreateRouteDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  origin: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  destination: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  code: string;

  @ApiProperty({ type: [CreateRouteStopDto], required: false })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateRouteStopDto)
  stops?: CreateRouteStopDto[];
}

export class UpdateRouteDto {
  @ApiProperty({ enum: RouteStatus })
  @IsEnum(RouteStatus)
  status: RouteStatus;
}
