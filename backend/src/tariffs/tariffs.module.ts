import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TariffsService } from './tariffs.service';
import { TariffsController } from './tariffs.controller';
import { Tariff } from './entities/tariff.entity';
import { TariffRule } from './entities/tariff-rule.entity';
import { RoutesModule } from '../routes/routes.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Tariff, TariffRule]),
    RoutesModule,
  ],
  controllers: [TariffsController],
  providers: [TariffsService],
  exports: [TariffsService],
})
export class TariffsModule {}
