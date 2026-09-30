import { Module } from '@nestjs/common';
import { FaresService } from './fares.service';
import { FaresController } from './fares.controller';
import { TariffsModule } from '../tariffs/tariffs.module';
import { RoutesModule } from '../routes/routes.module';

@Module({
  imports: [TariffsModule, RoutesModule],
  providers: [FaresService],
  controllers: [FaresController],
  exports: [FaresService],
})
export class FaresModule {}
