import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Request } from 'express';
import { CustomLogger } from '../logger/custom.logger';

@Injectable()
export class LoggerInterceptor implements NestInterceptor {
  constructor(private readonly logger: CustomLogger) {}

  intercept(context: ExecutionContext, next: CallHandler) {
    const request = context.switchToHttp().getRequest<Request>();

    // Set requestId and userId on the logger instance for this request
    this.logger.setRequest(request);

    // You can also log request details here
    // this.logger.log(`Incoming Request: ${request.method} ${request.url}`, 'Request', { requestId: request.requestId, userId: request.user?.sub });

    return next.handle();
  }
}
