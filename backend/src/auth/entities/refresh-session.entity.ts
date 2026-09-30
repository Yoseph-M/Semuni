import { Entity, Column, Index } from 'typeorm';
import { BaseEntity } from '../../common/entities/base.entity';

/**
 * A server-side record of one issued refresh token.
 *
 * Refresh tokens are deliberately **not** stateless: every one is persisted here
 * so it can be rotated when used and revoked on logout. Only a SHA-256 hash of
 * the token is stored, so a database leak does not hand out usable credentials.
 */
@Entity('refresh_sessions')
export class RefreshSession extends BaseEntity {
  /** The user this session authenticates. Indexed for "revoke all my sessions". */
  @Column()
  @Index()
  userId: string;

  /** The JWT `jti` claim — the lookup key for a presented refresh token. */
  @Column({ unique: true })
  jti: string;

  /** SHA-256 of the raw refresh token. Never the token itself. */
  @Column()
  tokenHash: string;

  @Column({ type: 'timestamp with time zone' })
  expiresAt: Date;

  /** Set when the session is revoked (logout or rotation). */
  @Column({ type: 'timestamp with time zone', nullable: true })
  revokedAt?: Date;

  /**
   * The `jti` of the session this one was rotated into. Used to detect reuse of
   * a rotated-away token.
   */
  @Column({ nullable: true })
  replacedByJti?: string;
}
