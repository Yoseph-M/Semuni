import {
  IsString,
  IsNotEmpty,
  IsEnum,
  IsIn,
  IsOptional,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { UserRole } from '../../common/enums';

/** Login handle rules — letters, digits, dot, underscore and hyphen. */
const USERNAME_PATTERN = /^[a-zA-Z0-9._-]+$/;
const USERNAME_EXAMPLE = 'testpassenger';

/**
 * Minimum password length enforced server-side at registration.
 * Deliberately modest — length is the main lever, and the target users are on
 * mobile keyboards. Not a substitute for the hashing done in UsersService.
 */
export const MIN_PASSWORD_LENGTH = 8;

export class LoginDto {
  @ApiProperty({
    example: USERNAME_EXAMPLE,
    description: 'Unique login handle. Phone numbers are not accepted here.',
  })
  @IsString()
  @IsNotEmpty()
  username: string;

  @ApiProperty({ example: '••••••••' })
  @IsString()
  @IsNotEmpty()
  password: string;

  @ApiProperty({ enum: UserRole, default: UserRole.PASSENGER })
  @IsEnum(UserRole)
  role: UserRole;
}

export class RegisterDto {
  @ApiProperty({
    example: USERNAME_EXAMPLE,
    description: 'Unique login handle used to sign in.',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(32)
  @Matches(USERNAME_PATTERN, {
    message:
      'username may only contain letters, numbers, dots, underscores and hyphens',
  })
  username: string;

  @ApiProperty({
    example: '+2519XXXXXXXX',
    required: false,
    description: 'Optional contact number.',
  })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiProperty({ example: 'Full legal name' })
  @IsString()
  @IsNotEmpty()
  fullName: string;

  @ApiProperty({ example: '••••••••', minLength: MIN_PASSWORD_LENGTH })
  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH, {
    message: `password must be at least ${MIN_PASSWORD_LENGTH} characters`,
  })
  password: string;

  @ApiProperty({
    enum: [UserRole.PASSENGER, UserRole.DRIVER],
    default: UserRole.PASSENGER,
    description:
      'Self-registration is limited to PASSENGER and DRIVER. Admin accounts are provisioned out-of-band.',
  })
  @IsIn([UserRole.PASSENGER, UserRole.DRIVER], {
    message: 'role must be either PASSENGER or DRIVER',
  })
  role: UserRole;

  @ApiProperty({ example: 'Ministry of Transport license reference', required: false })
  @IsOptional()
  @IsString()
  licenseNumber?: string; // Required if role is DRIVER
}

export class RefreshTokenDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  refreshToken: string;
}

export class LogoutDto {
  @ApiProperty({
    required: false,
    description:
      'Refresh token to revoke. When omitted, every active session for the caller is revoked.',
  })
  @IsOptional()
  @IsString()
  refreshToken?: string;
}
