import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds `refresh_sessions`.
 *
 * Refresh tokens were previously stateless JWTs with no server-side record, so
 * logout could not actually invalidate them and a stolen token stayed valid for
 * its full lifetime. Each issued refresh token now gets a row here (storing only
 * a SHA-256 hash) so it can be rotated on use and revoked on logout.
 */
export class AddRefreshSessions1790718000000 implements MigrationInterface {
  name = 'AddRefreshSessions1790718000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TABLE "refresh_sessions" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "userId" uuid NOT NULL,
        "jti" character varying NOT NULL,
        "tokenHash" character varying NOT NULL,
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "revokedAt" TIMESTAMP WITH TIME ZONE,
        "replacedByJti" character varying,
        CONSTRAINT "UQ_refresh_sessions_jti" UNIQUE ("jti"),
        CONSTRAINT "PK_refresh_sessions" PRIMARY KEY ("id")
      )`,
    );

    await queryRunner.query(
      `CREATE INDEX "IDX_refresh_sessions_userId" ON "refresh_sessions" ("userId")`,
    );

    await queryRunner.query(
      `ALTER TABLE "refresh_sessions" ADD CONSTRAINT "FK_refresh_sessions_userId"
         FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "refresh_sessions" DROP CONSTRAINT "FK_refresh_sessions_userId"`,
    );
    await queryRunner.query(`DROP INDEX "IDX_refresh_sessions_userId"`);
    await queryRunner.query(`DROP TABLE "refresh_sessions"`);
  }
}
