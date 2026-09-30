import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Settlement } from './entities/settlement.entity';
import { SettlementsService } from './settlements.service';
import { SettlementsController } from './settlements.controller';
import { Withdrawal } from '../withdrawals/entities/withdrawal.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Settlement, Withdrawal])],
  providers: [SettlementsService],
  controllers: [SettlementsController],
  exports: [SettlementsService],
})
export class SettlementsModule {}
