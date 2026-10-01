import { MigrationInterface, QueryRunner } from 'typeorm';

export class EnforceTransportationStopReferences1790730000000
  implements MigrationInterface
{
  name = 'EnforceTransportationStopReferences1790730000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // A route cannot contain two stops at the same sequence position.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_route_stop_sequence" ON "route_stops" ("routeId", "sequence")`,
    );

    // Preserve existing trip rows. New application writes populate these fields;
    // legacy rows are backfilled where an unambiguous route/stop match exists.
    await queryRunner.query(
      `ALTER TABLE "trips" ADD COLUMN "originStopId" uuid`,
    );
    await queryRunner.query(
      `ALTER TABLE "trips" ADD COLUMN "destinationStopId" uuid`,
    );

    await queryRunner.query(`
      UPDATE "trips" t
      SET "originStopId" = origin_stop.id,
          "destinationStopId" = destination_stop.id
      FROM "route_stops" origin_stop
      JOIN "route_stops" destination_stop
        ON destination_stop."routeId" = origin_stop."routeId"
      WHERE t."routeId" = origin_stop."routeId"
        AND LOWER(TRIM(t."origin")) = LOWER(TRIM(origin_stop."name"))
        AND LOWER(TRIM(t."destination")) = LOWER(TRIM(destination_stop."name"))
        AND origin_stop."sequence" < destination_stop."sequence"
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_trips_originStopId" ON "trips" ("originStopId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_trips_destinationStopId" ON "trips" ("destinationStopId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."IDX_trips_destinationStopId"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_trips_originStopId"`,
    );
    await queryRunner.query(
      `ALTER TABLE "trips" DROP COLUMN "destinationStopId"`,
    );
    await queryRunner.query(
      `ALTER TABLE "trips" DROP COLUMN "originStopId"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."UQ_route_stop_sequence"`,
    );
  }
}
