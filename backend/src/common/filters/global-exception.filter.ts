import { ExceptionFilter, Catch, ArgumentsHost, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { FastifyReply } from 'fastify';
import { DomainException } from '../domain.exception';
import { ErrorCode } from '../error-codes';

/**
 * Global exception filter for standardized error responses.
 *
 * Ensures all errors conform to the structure:
 * {
 *   "statusCode": 400,
 *   "message": "...",
 *   "error": "...",
 *   "code": "..."
 * }
 */
interface ErrorResponseBody {
  message?: string | string[];
  error?: string;
}

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<FastifyReply>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message: string | string[] = 'Internal server error';
    let error = 'Internal Server Error';
    let code = ErrorCode.INTERNAL_ERROR;

    if (exception instanceof DomainException) {
      status = exception.getStatus();
      const responseBody = exception.getResponse() as ErrorResponseBody;
      message = responseBody.message ?? exception.message;
      error = responseBody.error ?? error;
      code = exception.code;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      const responseBody = exception.getResponse() as string | ErrorResponseBody;
      
      // Handle class-validator errors gracefully
      if (typeof responseBody === 'object' && responseBody !== null) {
        message = responseBody.message || exception.message;
        error = responseBody.error || HttpStatus[status]?.replace(/_/g, ' ');
      } else {
        message = exception.message;
        error = HttpStatus[status]?.replace(/_/g, ' ');
      }
      
      if (status === HttpStatus.BAD_REQUEST) {
        code = ErrorCode.VALIDATION_ERROR;
      } else if (status === HttpStatus.FORBIDDEN) {
        code = ErrorCode.AUTH_FORBIDDEN;
      }
    } else if (exception instanceof Error) {
      this.logger.error(`Unhandled Exception: ${exception.message}`, exception.stack);
    } else {
      this.logger.error(`Unknown Exception: ${JSON.stringify(exception)}`);
    }

    response.status(status).send({
      statusCode: status,
      message,
      error,
      code,
    });
  }
}
