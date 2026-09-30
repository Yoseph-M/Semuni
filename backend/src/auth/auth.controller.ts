import { Controller, Post, Body, Get, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import {
  LoginDto,
  RegisterDto,
  RefreshTokenDto,
  LogoutDto,
} from './dto/auth.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { CurrentUser } from './decorators/current-user.decorator';
import { User } from '../users/entities/user.entity';

/**
 * Auth endpoints are rate limited far more tightly than the global default
 * (ThrottlerModule). Limits are env-overridable so tests and ops can adjust them
 * without a code change.
 */
const AUTH_THROTTLE_TTL = Number(process.env.AUTH_THROTTLE_TTL ?? 60_000);
const AUTH_REGISTER_LIMIT = Number(process.env.AUTH_THROTTLE_REGISTER_LIMIT ?? 5);
const AUTH_LOGIN_LIMIT = Number(process.env.AUTH_THROTTLE_LOGIN_LIMIT ?? 10);
const AUTH_REFRESH_LIMIT = Number(process.env.AUTH_THROTTLE_REFRESH_LIMIT ?? 20);

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @Throttle({ default: { limit: AUTH_REGISTER_LIMIT, ttl: AUTH_THROTTLE_TTL } })
  @ApiOperation({ summary: 'Register a new passenger or driver' })
  @ApiResponse({ status: 201, description: 'User registered successfully' })
  @ApiResponse({ status: 400, description: 'Validation failed' })
  @ApiResponse({ status: 409, description: 'User already exists' })
  async register(@Body() dto: RegisterDto) {
    const tokens = await this.authService.register(dto);
    return { data: tokens, meta: { message: 'Registration successful' } };
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: AUTH_LOGIN_LIMIT, ttl: AUTH_THROTTLE_TTL } })
  @ApiOperation({ summary: 'Login with username and password' })
  @ApiResponse({ status: 200, description: 'Login successful' })
  @ApiResponse({ status: 401, description: 'Invalid credentials' })
  async login(@Body() dto: LoginDto) {
    const tokens = await this.authService.login(dto);
    return { data: tokens, meta: { message: 'Login successful' } };
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: AUTH_REFRESH_LIMIT, ttl: AUTH_THROTTLE_TTL } })
  @ApiOperation({ summary: 'Refresh access token using refresh token' })
  @ApiResponse({ status: 200, description: 'Token refreshed' })
  @ApiResponse({ status: 401, description: 'Invalid refresh token' })
  async refresh(@Body() dto: RefreshTokenDto) {
    const tokens = await this.authService.refreshTokens(dto.refreshToken);
    return { data: tokens, meta: { message: 'Token refreshed' } };
  }

  @ApiBearerAuth('access-token')
  @UseGuards(JwtAuthGuard)
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Logout — revokes the refresh session' })
  @ApiResponse({ status: 200, description: 'Refresh session revoked' })
  async logout(@CurrentUser() user: User, @Body() dto: LogoutDto) {
    await this.authService.logout(user.id, dto?.refreshToken);
    return { data: null, meta: { message: 'Logout successful' } };
  }

  @ApiBearerAuth('access-token')
  @UseGuards(JwtAuthGuard)
  @Get('me')
  @ApiOperation({ summary: 'Get current authenticated user profile' })
  async getMe(@CurrentUser() user: User) {
    // Hide password hash
    const { passwordHash, ...safeUser } = user;
    return { data: safeUser, meta: {} };
  }
}
