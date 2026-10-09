import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import {
  HealthCheckService,
  TypeOrmHealthIndicator,
  HealthCheck,
  HealthIndicatorService,
} from '@nestjs/terminus';
import { DataSource } from 'typeorm';

@ApiTags('Health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly db: TypeOrmHealthIndicator,
    private readonly indicator: HealthIndicatorService,
    private readonly dataSource: DataSource,
  ) {}

  /** Liveness: the process is up. No dependencies, so a DB outage doesn't restart pods. */
  @Get('live')
  @ApiOperation({ summary: 'Liveness probe (process only)' })
  live() {
    return { status: 'ok' };
  }

  /** Readiness: DB reachable and schema fully migrated. */
  @Get(['', 'ready'])
  @HealthCheck()
  @ApiOperation({ summary: 'Readiness probe (DB connectivity + no pending migrations)' })
  async ready() {
    return this.health.check([
      () => this.db.pingCheck('database', { timeout: 3000 }),
      async () => {
        const check = this.indicator.check('migrations');
        const pending = await this.dataSource.showMigrations();
        return pending ? check.down({ pending: true }) : check.up();
      },
    ]);
  }
}
