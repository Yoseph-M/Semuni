import { HttpException, HttpStatus } from '@nestjs/common';
import { ErrorCode } from './error-codes';

/**
 * Custom domain exception that carries a machine-readable error code.
 *
 * Example usage:
 *   throw new DomainException(
 *     'Insufficient wallet balance',
 *     HttpStatus.BAD_REQUEST,
 *     ErrorCode.WALLET_INSUFFICIENT_BALANCE,
 *   );
 */
export class DomainException extends HttpException {
  constructor(
    message: string,
    status: HttpStatus,
    public readonly code: ErrorCode,
  ) {
    super(
      {
        statusCode: status,
        message,
        error: HttpStatus[status]?.replace(/_/g, ' ') ?? 'Error',
        code,
      },
      status,
    );
  }
}
