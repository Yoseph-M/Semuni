import { Entity, Column, Check } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';
import { UserRole, UserStatus } from '../../common/enums';

@Entity('users')
@Check('CHK_users_failed_login_attempts_nonnegative', '"failedLoginAttempts" >= 0')
export class User extends BaseEntity {
  /** Unique login handle — the identity used by /auth/login. */
  @Column({ unique: true })
  username: string;

  /** Optional contact detail, used for SMS/push once that lands. */
  @Column({ nullable: true, unique: true })
  phone?: string;

  @Column({ nullable: true })
  email?: string;

  @Column()
  passwordHash: string;

  @Column({ type: 'enum', enum: UserRole, default: UserRole.PASSENGER })
  role: UserRole;

  @Column({ type: 'enum', enum: UserStatus, default: UserStatus.ACTIVE })
  status: UserStatus;

  @Column({ type: 'timestamp with time zone', nullable: true })
  lastLoginAt?: Date;

  /** Consecutive failed password attempts since the last success or lockout. */
  @Column({ type: 'integer', default: 0, select: false })
  failedLoginAttempts: number;

  /** Login is refused until this instant after too many failed attempts. */
  @Column({ type: 'timestamp with time zone', nullable: true })
  lockedUntil?: Date | null;
}
