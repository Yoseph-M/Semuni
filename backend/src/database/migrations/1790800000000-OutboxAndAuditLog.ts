import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * notification_outbox: notifications queued in the same transaction as the
 * event, delivered by `npm run notifications:dispatch`.
 * audit_logs: append-only record of every mutating API call.
 */

export class OutboxAndAuditLog1790800000000 implements MigrationInterface {
    name = 'OutboxAndAuditLog1790800000000'

    public async up(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`CREATE TABLE "notification_outbox" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), "userId" uuid NOT NULL, "channel" character varying(16) NOT NULL DEFAULT 'PUSH', "title" character varying(120) NOT NULL, "body" text NOT NULL, "data" jsonb, "status" character varying(16) NOT NULL DEFAULT 'PENDING', "attempts" integer NOT NULL DEFAULT '0', "nextAttemptAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), "sentAt" TIMESTAMP WITH TIME ZONE, "lastError" character varying(500), CONSTRAINT "PK_83d47c7dba1da2d038749fe757e" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE INDEX "IDX_notification_outbox_due" ON "notification_outbox" ("status", "nextAttemptAt") `);
        await queryRunner.query(`CREATE TABLE "audit_logs" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), "actorUserId" uuid, "actorRole" character varying(32), "action" character varying(200) NOT NULL, "resourceId" character varying(64), "statusCode" integer NOT NULL, "requestId" character varying(64), "ip" character varying(64), CONSTRAINT "PK_1bb179d048bbc581caa3b013439" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE INDEX "IDX_audit_logs_actorUserId" ON "audit_logs" ("actorUserId") `);
        await queryRunner.query(`CREATE INDEX "IDX_audit_logs_createdAt" ON "audit_logs" ("createdAt") `);
        await queryRunner.query(`
      CREATE FUNCTION audit_logs_append_only() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit_logs is append-only: % is not allowed', TG_OP
          USING ERRCODE = 'restrict_violation';
      END
      $$`);
        await queryRunner.query(`CREATE TRIGGER "TRG_audit_logs_append_only" BEFORE UPDATE OR DELETE ON "audit_logs" FOR EACH ROW EXECUTE FUNCTION audit_logs_append_only()`);
        await queryRunner.query(`CREATE TRIGGER "TRG_audit_logs_no_truncate" BEFORE TRUNCATE ON "audit_logs" FOR EACH STATEMENT EXECUTE FUNCTION audit_logs_append_only()`);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`DROP TRIGGER "TRG_audit_logs_no_truncate" ON "audit_logs"`);
        await queryRunner.query(`DROP TRIGGER "TRG_audit_logs_append_only" ON "audit_logs"`);
        await queryRunner.query(`DROP FUNCTION audit_logs_append_only()`);
        await queryRunner.query(`DROP INDEX "public"."IDX_audit_logs_createdAt"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_audit_logs_actorUserId"`);
        await queryRunner.query(`DROP TABLE "audit_logs"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_notification_outbox_due"`);
        await queryRunner.query(`DROP TABLE "notification_outbox"`);
    }

}
