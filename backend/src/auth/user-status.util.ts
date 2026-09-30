import { ErrorCode } from '../common/error-codes';
import { UserStatus } from '../common/enums';

/**
 * Maps a non-ACTIVE account status to the error code and message returned to
 * the client.
 *
 * Policy: only `ACTIVE` accounts may authenticate or use protected endpoints.
 * `PENDING` is treated as denied until an operator activates the account, so a
 * freshly created but unactivated user cannot authenticate.
 */
export function nonActiveStatusError(status: UserStatus): {
  code: ErrorCode;
  message: string;
} {
  switch (status) {
    case UserStatus.SUSPENDED:
      return {
        code: ErrorCode.AUTH_USER_SUSPENDED,
        message: 'This account has been suspended.',
      };
    case UserStatus.INACTIVE:
      return {
        code: ErrorCode.AUTH_USER_INACTIVE,
        message: 'This account is inactive.',
      };
    case UserStatus.PENDING:
    default:
      return {
        code: ErrorCode.AUTH_USER_PENDING,
        message: 'This account is not active yet.',
      };
  }
}
