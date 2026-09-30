import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Route } from './entities/route.entity';
import { RouteStop } from './entities/route-stop.entity';
import { RoutesService } from './routes.service';
import { RoutesController } from './routes.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Route, RouteStop])],
  providers: [RoutesService],
  controllers: [RoutesController],
  exports: [RoutesService, TypeOrmModule],
})
export class RoutesModule {}
