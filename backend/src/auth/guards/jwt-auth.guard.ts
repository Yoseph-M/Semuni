import { Injectable, ExecutionContext, HttpStatus } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { DomainException } from '../../common/domain.exception';
import { ErrorCode } from '../../common/error-codes';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  canActivate(context: ExecutionContext) {
    return super.canActivate(context);
  }

  handleRequest<TUser = unknown>(err: unknown, user: TUser | false | null): TUser {
    if (err || !user) {
      throw err || new DomainException(
        'Invalid or expired token',
        HttpStatus.UNAUTHORIZED,
        ErrorCode.AUTH_TOKEN_INVALID,
      );
    }
    return user;
  }
}
