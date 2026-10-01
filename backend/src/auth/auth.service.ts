import { Injectable, HttpStatus } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import * as bcrypt from 'bcrypt';
import type { StringValue } from 'ms';
import { UsersService } from '../users/users.service';
import { PassengersService } from '../passengers/passengers.service';
import { DriversService } from '../drivers/drivers.service';
import { RefreshTokensService } from './refresh-tokens.service';
import { LoginDto, RegisterDto } from './dto/auth.dto';
import { nonActiveStatusError } from './user-status.util';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';
import { UserRole, UserStatus } from '../common/enums';

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly passengersService: PassengersService,
    private readonly driversService: DriversService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly refreshTokensService: RefreshTokensService,
    private readonly dataSource: DataSource,
  ) {}

  async register(dto: RegisterDto) {
    // Clients may only self-register as a passenger or a driver. Admin accounts
    // are provisioned out-of-band (seed / ops) and never through the public API.
    if (dto.role !== UserRole.PASSENGER && dto.role !== UserRole.DRIVER) {
      throw new DomainException(
        'Only passenger and driver accounts can be self-registered',
        HttpStatus.FORBIDDEN,
        ErrorCode.AUTH_FORBIDDEN,
      );
    }

    if (dto.role === UserRole.DRIVER && !dto.licenseNumber) {
      throw new DomainException(
        'License number is required for drivers',
        HttpStatus.BAD_REQUEST,
        ErrorCode.VALIDATION_ERROR,
      );
    }

    // The user row and its role profile are created together, so a failure while
    // creating the profile (e.g. a duplicate driver licence) must not leave an
    // orphaned user holding the username.
    const user = await this.dataSource.transaction(async (manager) => {
      const created = await this.usersService.create(
        {
          username: dto.username,
          phone: dto.phone,
          passwordHash: dto.password,
          role: dto.role,
        },
        manager,
      );

      if (dto.role === UserRole.PASSENGER) {
        await this.passengersService.create(created, dto.fullName, manager);
      } else {
        await this.driversService.create(
          created,
          dto.fullName,
          dto.licenseNumber!,
          manager,
        );
      }

      return created;
    });

    return this.generateTokens(user.id, user.role);
  }

  async login(dto: LoginDto) {
    const user = await this.usersService.findByUsername(dto.username);
    if (!user || user.role !== dto.role) {
      // Identical response for "no such user" and "wrong role" so the endpoint
      // does not reveal whether an account exists.
      throw new DomainException(
        'Invalid username or password',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_INVALID_CREDENTIALS,
      );
    }

    const isPasswordValid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isPasswordValid) {
      throw new DomainException(
        'Invalid username or password',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_INVALID_CREDENTIALS,
      );
    }

    // Checked only after the password is verified so account status is never
    // leaked to someone who does not already know the credentials.
    if (user.status !== UserStatus.ACTIVE) {
      const { code, message } = nonActiveStatusError(user.status);
      throw new DomainException(message, HttpStatus.FORBIDDEN, code);
    }

    await this.usersService.updateLastLogin(user.id);
    return this.generateTokens(user.id, user.role);
  }

  /**
   * Exchanges a refresh token for a fresh token pair.
   *
   * The presented token is rotated (revoked) and replaced, so a refresh token is
   * single-use. Reusing a rotated-away token revokes the whole session chain.
   */
  async refreshTokens(refreshToken: string) {
    const rotated = await this.refreshTokensService.rotate(refreshToken);

    // Rotation is not enough on its own: a refresh token issued before a
    // suspension/status change must not mint fresh access tokens. Checked after
    // rotation (so the presented token is consumed either way) and the whole
    // session chain is revoked when the account is no longer ACTIVE.
    const user = await this.usersService.findById(rotated.userId);
    if (!user) {
      await this.refreshTokensService.revokeAllForUser(rotated.userId);
      throw new DomainException(
        'Invalid refresh token',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_REFRESH_TOKEN_INVALID,
      );
    }
    if (user.status !== UserStatus.ACTIVE) {
      await this.refreshTokensService.revokeAllForUser(user.id);
      const { code, message } = nonActiveStatusError(user.status);
      throw new DomainException(message, HttpStatus.FORBIDDEN, code);
    }

    // Role is read from the stored user, not from the old token payload.
    const accessToken = await this.signAccessToken(user.id, user.role);

    return {
      accessToken,
      refreshToken: rotated.refreshToken,
      user: { id: user.id, role: user.role },
    };
  }

  /**
   * Invalidates the caller's refresh session(s).
   *
   * When the caller supplies the refresh token being logged out we revoke
   * exactly that session; otherwise every active session for the user is
   * revoked (logout-everywhere), so logout can never leave a usable refresh
   * credential behind.
   */
  async logout(userId: string, refreshToken?: string): Promise<void> {
    if (refreshToken) {
      const revoked = await this.refreshTokensService.revoke(refreshToken, userId);
      if (revoked) return;
    }
    await this.refreshTokensService.revokeAllForUser(userId);
  }

  private async signAccessToken(
    userId: string,
    role: UserRole,
  ): Promise<string> {
    return this.jwtService.signAsync(
      { sub: userId, role },
      {
        secret: this.configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
        expiresIn: (this.configService.get<string>('JWT_ACCESS_EXPIRES_IN') ??
          '15m') as StringValue,
      },
    );
  }

  private async generateTokens(userId: string, role: UserRole) {
    const [accessToken, refreshToken] = await Promise.all([
      this.signAccessToken(userId, role),
      this.refreshTokensService.issue(userId, role),
    ]);

    return {
      accessToken,
      refreshToken,
      // Non-sensitive identity so a client can pick the right surface
      // (passenger vs driver vs admin) without a second round-trip.
      user: { id: userId, role },
    };
  }
}
