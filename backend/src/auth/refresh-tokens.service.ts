import { Injectable, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { Repository } from 'typeorm';
import { createHash } from 'node:crypto';
import { v4 as uuidv4 } from 'uuid';
import type { StringValue } from 'ms';
import { RefreshSession } from './entities/refresh-session.entity';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { UserRole } from '../common/enums';

interface RefreshPayload {
  sub?: string;
  role?: UserRole;
  jti?: string;
}

/**
 * Owns the refresh-token lifecycle.
 *
 * Responsibilities:
 *   * issue   — sign a refresh JWT and persist its session (hash only)
 *   * rotate  — validate a presented token, revoke it, issue a replacement
 *   * revoke  — invalidate a single session (logout)
 *   * revokeAllForUser — invalidate every session (logout-everywhere / reuse)
 *
 * Tokens are signed with a dedicated secret (`JWT_REFRESH_SECRET`) that is
 * distinct from the access-token secret, so an access token can never be
 * replayed as a refresh token.
 */
@Injectable()
export class RefreshTokensService {
  constructor(
    @InjectRepository(RefreshSession)
    private readonly sessions: Repository<RefreshSession>,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  private get secret(): string {
    return this.configService.getOrThrow<string>('JWT_REFRESH_SECRET');
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  /** Signs a new refresh token and persists its session. */
  async issue(userId: string, role: UserRole): Promise<string> {
    const jti = uuidv4();
    const token = await this.jwtService.signAsync(
      { sub: userId, role, jti },
      {
        secret: this.secret,
        expiresIn: (this.configService.get<string>('JWT_REFRESH_EXPIRES_IN') ??
          '7d') as StringValue,
      },
    );

    // Read the expiry from the token itself so the stored row and the JWT can
    // never drift apart.
    const decoded = this.jwtService.decode(token) as { exp?: number } | null;
    const expiresAt = decoded?.exp
      ? new Date(decoded.exp * 1000)
      : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await this.sessions.save(
      this.sessions.create({
        userId,
        jti,
        tokenHash: this.hash(token),
        expiresAt,
      }),
    );

    return token;
  }

  /**
   * Verifies a refresh token against its stored session.
   *
   * Reusing a token whose session was already revoked is treated as a
   * token-theft signal: every session for that user is revoked.
   */
  private async load(
    token: string,
  ): Promise<{ session: RefreshSession; payload: Required<RefreshPayload> }> {
    let payload: RefreshPayload;
    try {
      payload = await this.jwtService.verifyAsync<RefreshPayload>(token, {
        secret: this.secret,
      });
    } catch (err) {
      const expired = (err as { name?: string })?.name === 'TokenExpiredError';
      throw new DomainException(
        'Invalid or expired refresh token',
        HttpStatus.UNAUTHORIZED,
        expired
          ? ErrorCode.AUTH_REFRESH_TOKEN_EXPIRED
          : ErrorCode.AUTH_REFRESH_TOKEN_INVALID,
      );
    }

    if (!payload?.jti || !payload?.sub || !payload?.role) {
      throw new DomainException(
        'Invalid refresh token',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_REFRESH_TOKEN_INVALID,
      );
    }

    const session = await this.sessions.findOne({
      where: { jti: payload.jti },
    });

    if (!session || session.tokenHash !== this.hash(token)) {
      throw new DomainException(
        'Invalid refresh token',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_REFRESH_TOKEN_INVALID,
      );
    }

    if (session.revokedAt) {
      // A revoked token was presented again. Assume the credential chain leaked
      // and revoke every session belonging to the user.
      await this.revokeAllForUser(session.userId);
      throw new DomainException(
        'Refresh token has been revoked',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_REFRESH_TOKEN_REVOKED,
      );
    }

    if (session.expiresAt.getTime() <= Date.now()) {
      throw new DomainException(
        'Refresh token has expired',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_REFRESH_TOKEN_EXPIRED,
      );
    }

    return {
      session,
      payload: {
        sub: payload.sub,
        role: payload.role,
        jti: payload.jti,
      },
    };
  }

  /**
   * Validates the presented refresh token, revokes it, and issues a replacement.
   * Returns the new refresh token plus the identity it belongs to.
   */
  async rotate(token: string): Promise<{
    userId: string;
    role: UserRole;
    refreshToken: string;
  }> {
    const { session, payload } = await this.load(token);

    const refreshToken = await this.issue(payload.sub, payload.role);
    const replacement = this.jwtService.decode(refreshToken) as {
      jti?: string;
    } | null;

    session.revokedAt = new Date();
    session.replacedByJti = replacement?.jti;
    await this.sessions.save(session);

    return { userId: payload.sub, role: payload.role, refreshToken };
  }

  /**
   * Revokes the session behind [token] if it belongs to [userId].
   *
   * Returns true when a session was found and revoked. Never throws: logout
   * must succeed even for an already-invalid token.
   */
  async revoke(token: string, userId: string): Promise<boolean> {
    let payload: RefreshPayload;
    try {
      payload = await this.jwtService.verifyAsync<RefreshPayload>(token, {
        secret: this.secret,
      });
    } catch {
      return false;
    }

    if (!payload?.jti) return false;

    const session = await this.sessions.findOne({ where: { jti: payload.jti } });
    if (!session || session.userId !== userId || session.revokedAt) {
      return false;
    }

    session.revokedAt = new Date();
    await this.sessions.save(session);
    return true;
  }

  /** Revokes every active session for a user. */
  async revokeAllForUser(userId: string): Promise<void> {
    await this.sessions
      .createQueryBuilder()
      .update(RefreshSession)
      .set({ revokedAt: () => 'now()' })
      .where('"userId" = :userId AND "revokedAt" IS NULL', { userId })
      .execute();
  }
}
