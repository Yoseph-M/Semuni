import { IsString, IsNotEmpty, IsEnum, IsOptional, IsArray, ValidateNested, IsInt, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty } from '@nestjs/swagger';
import { RouteStatus } from '../../common/enums';

export class CreateRouteStopDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty()
  @IsInt()
  @Min(1)
  sequence: number;

  @ApiProperty({ required: false })
  @IsOptional()
  @Min(-90)
  latitude?: number;

  @ApiProperty({ required: false })
  @IsOptional()
  @Min(-180)
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
