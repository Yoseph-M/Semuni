/**
 * Semuni Backend — Entry Point
 *
 * Boots the NestJS application on the Fastify adapter.
 * Configures Swagger, CORS, Helmet, global validation, and versioning.
 */
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from '@fastify/helmet';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';
import { CustomLogger } from './common/logger/custom.logger';
import { loadBackendEnv } from './database/load-env';

// The Fastify adapter is built before ConfigModule runs, so .env is loaded here
// for the adapter-level options (trustProxy).
loadBackendEnv();

/** `TRUST_PROXY`: unset/false, true, a hop count, or a comma list of proxy IPs/CIDRs. */
function parseTrustProxy(
  value?: string,
): boolean | string[] | ((address: string, hop: number) => boolean) {
  if (!value || value === 'false') return false;
  if (value === 'true') return true;
  if (/^\d+$/.test(value)) {
    const hops = Number(value);
    return (_address, hop) => hop < hops;
  }
  return value.split(',').map((v) => v.trim());
}

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({ trustProxy: parseTrustProxy(process.env.TRUST_PROXY) }),
    {
      bufferLogs: true,
      logger: new CustomLogger(),
    },
  );
  // CustomLogger is Scope.TRANSIENT, so it must be resolved rather than fetched.
  app.useLogger(await app.resolve(CustomLogger));

  const configService = app.get(ConfigService);
  const port = configService.get<number>('PORT', 3000);
  const apiPrefix = configService.get<string>('API_PREFIX', 'api/v1');
  const corsOrigin = configService.get<string>('CORS_ORIGIN', '*');

  // ─── Global prefix & versioning ────────────────────────
  app.setGlobalPrefix(apiPrefix);

  // ─── CORS ──────────────────────────────────────────────
  // A wildcard origin never carries credentials; explicit origins may.
  const wildcardCors = corsOrigin === '*';
  app.enableCors({
    origin: wildcardCors ? true : corsOrigin.split(',').map((o) => o.trim()),
    credentials: !wildcardCors,
  });

  const swaggerEnabled =
    configService.get<string>('SWAGGER_ENABLED') === 'true' ||
    (configService.get<string>('SWAGGER_ENABLED') !== 'false' &&
      configService.get<string>('NODE_ENV') !== 'production');

  await app.register(helmet, {
    // Swagger UI needs inline scripts/styles; keep the default CSP otherwise.
    contentSecurityPolicy: swaggerEnabled ? false : undefined,
  });

  // ─── Global exception filter ──────────────────────────
  app.useGlobalFilters(new GlobalExceptionFilter());

  // ─── Global validation pipe ───────────────────────────
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
    }),
  );

  // ─── Swagger (off in production unless SWAGGER_ENABLED=true) ─────
  if (swaggerEnabled) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('Semuni API')
      .setDescription(
        'Semuni — Ethiopian digital minibus taxi fare, wallet, and payment platform API',
      )
      .setVersion('1.0')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
          name: 'Authorization',
          description: 'Enter JWT access token',
          in: 'header',
        },
        'access-token',
      )
      .addTag('Auth', 'Authentication & registration')
      .addTag('Passengers', 'Passenger profile & trips')
      .addTag('Drivers', 'Driver profile, earnings & withdrawals')
      .addTag('Wallet', 'Wallet balance, transactions & top-up')
      .addTag('Fares', 'Fare calculation')
      .addTag('Trips', 'Trip creation & history')
      .addTag('Payments', 'Trip payment processing')
      .addTag('Routes', 'Minibus routes')
      .addTag('Tariffs', 'Tariff management')
      .addTag('Admin', 'Administration')
      .addTag('Health', 'Health checks')
      .build();

    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('api/docs', app, document, {
      swaggerOptions: {
        persistAuthorization: true,
      },
    });
  }

  await app.listen(port, '0.0.0.0');

  const appLogger = await app.resolve(CustomLogger);
  appLogger.log(`🚐 Semuni backend running on http://localhost:${port}`, 'Bootstrap');
  if (swaggerEnabled) {
    appLogger.log(`📄 Swagger docs at http://localhost:${port}/api/docs`, 'Bootstrap');
  }
}

bootstrap();
