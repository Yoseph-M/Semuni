import { Module, NestModule, MiddlewareConsumer } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { PassengersModule } from './passengers/passengers.module';
import { DriversModule } from './drivers/drivers.module';
import { VehiclesModule } from './vehicles/vehicles.module';
import { RoutesModule } from './routes/routes.module';
import { TariffsModule } from './tariffs/tariffs.module';
import { FaresModule } from './fares/fares.module';
import { LedgerModule } from './ledger/ledger.module';
import { WalletsModule } from './wallets/wallets.module';
import { PaymentsModule } from './payments/payments.module';
import { WithdrawalsModule } from './withdrawals/withdrawals.module';
import { TripsModule } from './trips/trips.module';
import { NotificationsModule } from './notifications/notifications.module';
import { SettlementsModule } from './settlements/settlements.module';
import { HealthModule } from './health/health.module';
import { RequestIdMiddleware } from './common/middleware/request-id.middleware';
import { CustomLogger } from './common/logger/custom.logger';
import { LoggerInterceptor } from './common/interceptors/logger.interceptor';
import { validateEnv } from './config/env.validation';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env'],
      validate: validateEnv,
    }),
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => [
        {
          ttl: Number(config.get('THROTTLE_TTL', 60000)),
          limit: Number(config.get('THROTTLE_LIMIT', 100)),
        },
      ],
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres' as const,
        host: config.get<string>('DB_HOST', 'localhost'),
        port: Number(config.get('DB_PORT', 5432)),
        username: config.get<string>('DB_USERNAME', 'semuni'),
        password: config.get<string>('DB_PASSWORD', 'semuni_dev_password'),
        database: config.get<string>('DB_DATABASE', 'semuni'),
        autoLoadEntities: true,
        migrations: [__dirname + '/database/migrations/*.{ts,js}'],
        synchronize: false,
        logging: config.get('NODE_ENV') === 'development',
      }),
    }),
    AuthModule,
    UsersModule,
    PassengersModule,
    DriversModule,
    VehiclesModule,
    RoutesModule,
    TariffsModule,
    FaresModule,
    LedgerModule,
    WalletsModule,
    PaymentsModule,
    WithdrawalsModule,
    TripsModule,
    NotificationsModule,
    SettlementsModule,
    HealthModule,
  ],
  controllers: [],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    CustomLogger,
    {
      provide: APP_INTERCEPTOR,
      useClass: LoggerInterceptor,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}

