import { config } from 'dotenv';
import { resolve } from 'path';

/** Load backend/.env regardless of the process working directory. */
export function loadBackendEnv(): void {
  config({ path: resolve(__dirname, '..', '..', '.env') });
}
