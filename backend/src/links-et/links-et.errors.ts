import { HttpStatus } from '@nestjs/common';
import { DomainException } from '../common/domain.exception';
import { ErrorCode } from '../common/error-codes';

/**
 * Base exception for all links.et verification failures.
 */
export class LinksEtException extends DomainException {
  constructor(
    message: string,
    status: HttpStatus = HttpStatus.BAD_GATEWAY,
    code: ErrorCode = ErrorCode.LINKS_ET_UNAVAILABLE,
  ) {
    super(message, status, code);
  }
}

export class LinksEtBadRequestException extends LinksEtException {
  constructor(message = 'Invalid request to links.et') {
    super(message, HttpStatus.BAD_REQUEST, ErrorCode.LINKS_ET_BAD_REQUEST);
  }
}

export class LinksEtAuthException extends LinksEtException {
  constructor(message = 'links.et authentication failed: invalid API key') {
    super(message, HttpStatus.UNAUTHORIZED, ErrorCode.LINKS_ET_AUTH_FAILED);
  }
}

export class LinksEtRateLimitException extends LinksEtException {
  constructor(
    message = 'links.et rate limit exceeded',
    public readonly retryAfterSeconds?: number,
  ) {
    super(message, HttpStatus.TOO_MANY_REQUESTS, ErrorCode.LINKS_ET_RATE_LIMITED);
  }
}

export class LinksEtUnavailableException extends LinksEtException {
  constructor(message = 'links.et service is currently unavailable') {
    super(message, HttpStatus.BAD_GATEWAY, ErrorCode.LINKS_ET_UNAVAILABLE);
  }
}

export class LinksEtNotFoundException extends LinksEtException {
  constructor(message = 'Receipt or transaction not found on links.et') {
    super(message, HttpStatus.NOT_FOUND, ErrorCode.LINKS_ET_NOT_FOUND);
  }
}

export class LinksEtUnsupportedProviderException extends LinksEtException {
  constructor(provider: string) {
    super(
      `links.et does not support provider: ${provider}`,
      HttpStatus.UNPROCESSABLE_ENTITY,
      ErrorCode.LINKS_ET_UNSUPPORTED_PROVIDER,
    );
  }
}

export class LinksEtInvalidReceiptException extends LinksEtException {
  constructor(message = 'The provided receipt is invalid, unverified, or expired') {
    super(message, HttpStatus.UNPROCESSABLE_ENTITY, ErrorCode.LINKS_ET_INVALID_RECEIPT);
  }
}

export class LinksEtTimeoutException extends LinksEtException {
  constructor(message = 'links.et request timed out') {
    super(message, HttpStatus.GATEWAY_TIMEOUT, ErrorCode.LINKS_ET_TIMEOUT);
  }
}

export class LinksEtVerificationMismatchException extends LinksEtException {
  constructor(message = 'Receipt verification details do not match expected payment') {
    super(message, HttpStatus.CONFLICT, ErrorCode.LINKS_ET_VERIFICATION_MISMATCH);
  }
}
