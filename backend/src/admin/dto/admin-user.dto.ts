import { IsEmail, IsEnum, IsOptional, IsString, Matches, MinLength } from 'class-validator';
import { UserRole, UserStatus } from '../../common/enums';

const USERNAME_PATTERN = /^[a-zA-Z0-9._-]+$/;

export class CreateAdminUserDto {
  @IsString() @Matches(USERNAME_PATTERN) username: string;
  @IsString() @MinLength(8) password: string;
  @IsEnum(UserRole) role: UserRole;
  @IsEnum(UserStatus) @IsOptional() status?: UserStatus;
  @IsString() @IsOptional() phone?: string;
  @IsEmail() @IsOptional() email?: string;
}

export class UpdateAdminUserDto {
  @IsEnum(UserRole) @IsOptional() role?: UserRole;
  @IsEnum(UserStatus) @IsOptional() status?: UserStatus;
  @IsString() @IsOptional() phone?: string;
  @IsEmail() @IsOptional() email?: string;
  @IsString() @MinLength(8) @IsOptional() password?: string;
}
