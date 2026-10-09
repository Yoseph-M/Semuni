import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

/** Append-only (DB trigger) record of every state-changing API call. */
@Entity('audit_logs')
@Index('IDX_audit_logs_createdAt', ['createdAt'])
@Index('IDX_audit_logs_actorUserId', ['actorUserId'])
export class AuditLog {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @CreateDateColumn({ type: 'timestamp with time zone' })
  createdAt: Date;

  @Column({ type: 'uuid', nullable: true })
  actorUserId?: string;

  @Column({ type: 'varchar', length: 32, nullable: true })
  actorRole?: string;

  /** e.g. "POST /api/v1/withdrawals" — the route pattern, never the body. */
  @Column({ type: 'varchar', length: 200 })
  action: string;

  @Column({ type: 'varchar', length: 64, nullable: true })
  resourceId?: string;

  @Column({ type: 'int' })
  statusCode: number;

  @Column({ type: 'varchar', length: 64, nullable: true })
  requestId?: string;

  @Column({ type: 'varchar', length: 64, nullable: true })
  ip?: string;
}
