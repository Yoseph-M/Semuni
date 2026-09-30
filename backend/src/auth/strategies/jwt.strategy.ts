import { ExtractJwt, Strategy } from 'passport-jwt';
import { PassportStrategy } from '@nestjs/passport';
import { Injectable, UnauthorizedException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UsersService } from '../../users/users.service';
import { UserStatus } from '../../common/enums';
import { DomainException } from '../../common/domain.exception';
import { nonActiveStatusError } from '../user-status.util';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private readonly configService: ConfigService,
    private readonly usersService: UsersService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.getOrThrow<string>('JWT_ACCESS_SECRET'),
    });
  }

  async validate(payload: any) {
    const user = await this.usersService.findById(payload.sub);
    if (!user) {
      throw new UnauthorizedException();
    }
    // A suspended/inactive account loses access immediately rather than only
    // when its already-issued access token happens to expire.
    if (user.status !== UserStatus.ACTIVE) {
      const { code, message } = nonActiveStatusError(user.status);
      throw new DomainException(message, HttpStatus.FORBIDDEN, code);
    }
    // Returns full user object to the request
    return user;
  }
}
