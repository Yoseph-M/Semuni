import { Controller, Get, Query, BadRequestException } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { MapsService } from './maps.service';

@ApiTags('Maps')
@Controller('maps')
export class MapsController {
  constructor(private readonly mapsService: MapsService) {}

  @Get('config')
  @ApiOperation({ summary: 'Get map configuration, style URLs, and service status' })
  getConfig() {
    return {
      data: this.mapsService.getMapConfig(),
      meta: {},
    };
  }

  @Get('directions')
  @ApiOperation({ summary: 'Calculate directions/route between two coordinates' })
  @ApiQuery({ name: 'origin', description: 'Origin "lat,lon"', example: '9.0222,38.7468' })
  @ApiQuery({ name: 'destination', description: 'Destination "lat,lon"', example: '8.9950,38.7890' })
  async getDirections(
    @Query('origin') origin: string,
    @Query('destination') destination: string,
  ) {
    if (!origin || !destination) {
      throw new BadRequestException('Query parameters "origin" and "destination" are required');
    }
    const result = await this.mapsService.getDirections(origin, destination);
    return {
      data: result,
      meta: { source: result.source },
    };
  }

  @Get('geocode')
  @ApiOperation({ summary: 'Search places / forward geocoding' })
  @ApiQuery({ name: 'query', description: 'Search term (e.g. Bole, Piazza)' })
  async geocode(@Query('query') query: string) {
    const result = await this.mapsService.geocode(query);
    return {
      data: result.data,
      meta: {},
    };
  }
}
