import { MigrationInterface, QueryRunner } from "typeorm";

export class AddVehicleTypeToTariffRule1790675677668 implements MigrationInterface {
    name = 'AddVehicleTypeToTariffRule1790675677668'

    public async up(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`DO $$ BEGIN CREATE TYPE "public"."tariff_rules_vehicletype_enum" AS ENUM('MINIBUS'); EXCEPTION WHEN duplicate_object THEN null; END $$`);
        await queryRunner.query(`ALTER TABLE "tariff_rules" ADD COLUMN "vehicleType" "public"."tariff_rules_vehicletype_enum"`);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`ALTER TABLE "tariff_rules" DROP COLUMN "vehicleType"`);
        await queryRunner.query(`DROP TYPE "public"."tariff_rules_vehicletype_enum"`);
    }

}
