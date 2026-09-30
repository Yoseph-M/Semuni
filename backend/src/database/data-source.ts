import { DataSource, DataSourceOptions } from 'typeorm';
import { join } from 'path';
import { loadBackendEnv } from './load-env';

loadBackendEnv();

export function buildDataSourceOptions(
  env: NodeJS.ProcessEnv = process.env,
): DataSourceOptions {
  return {
    type: 'postgres',
    host: env.DB_HOST || 'localhost',
    port: parseInt(env.DB_PORT || '5432', 10),
    username: env.DB_USERNAME || 'semuni',
    password: env.DB_PASSWORD || 'semuni_dev_password',
    database: env.DB_DATABASE || 'semuni',
    entities: [join(__dirname, '..', '**', '*.entity.{ts,js}')],
    migrations: [join(__dirname, 'migrations', '*.{ts,js}')],
    synchronize: false,
    logging: env.NODE_ENV === 'development',
  };
}

export const dataSourceOptions = buildDataSourceOptions();

const dataSource = new DataSource(dataSourceOptions);
export default dataSource;
