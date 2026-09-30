import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { FaresService } from './fares.service';
import { CalculateFareDto } from './dto/fare.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('Fares')
@Controller('fares')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard)
export class FaresController {
  constructor(private readonly faresService: FaresService) {}

  @Post('calculate')
  @ApiOperation({ summary: 'Calculate fare for a given route and stops' })
  async calculateFare(@Body() dto: CalculateFareDto) {
    const fare = await this.faresService.calculateFare(dto);
    return { data: fare, meta: {} };
  }
}
