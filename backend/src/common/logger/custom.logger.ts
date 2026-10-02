import { ConsoleLogger, Injectable, Scope } from '@nestjs/common';
import { Request } from 'express';
import { IncomingMessage } from 'http';

interface CustomLogContext {
  requestId?: string;
  userId?: string;
  tripId?: string;
  paymentId?: string;
  transactionId?: string;
  // Add other relevant IDs here
  [key: string]: unknown;
}

@Injectable({ scope: Scope.TRANSIENT })
export class CustomLogger extends ConsoleLogger {
  private requestId?: string;
  private userId?: string;

  constructor() {
    // One JSON object per line in production (or LOG_FORMAT=json) for log
    // aggregation; human-readable output otherwise.
    const json =
      (process.env.LOG_FORMAT ??
        (process.env.NODE_ENV === 'production' ? 'json' : 'pretty')) === 'json';
    super({ json, colors: !json });
  }

  setContext(context: string) {
    super.setContext(context);
  }

  setRequest(request: Request | IncomingMessage) {
    if (request && 'requestId' in request) {
      this.requestId = (request as Request).requestId;
    }
    // JwtStrategy attaches the User entity (`id`); a raw JWT payload has `sub`.
    const user = (request as { user?: { id?: string; sub?: string } } | undefined)
      ?.user;
    if (user?.id || user?.sub) {
      this.userId = user.id ?? user.sub;
    }
  }

  // Standard signature for log / warn / debug / verbose:
  //   (message, context?, customContext?)
  // For error(), keep Nest's traditional (message, stackTrace?, context?, customContext?)

  log(message: unknown, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.log(message, enhancedContext);
  }

  error(
    message: unknown,
    traceOrStack?: string,
    context?: string,
    customContext?: CustomLogContext,
  ) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.error(message, traceOrStack, enhancedContext);
  }

  warn(message: unknown, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.warn(message, enhancedContext);
  }

  debug(message: unknown, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.debug(message, enhancedContext);
  }

  verbose(message: unknown, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.verbose(message, enhancedContext);
  }

  private getEnhancedContext(
    customContext?: CustomLogContext,
    contextOverride?: string,
  ): string {
    const contextObj: CustomLogContext = {
      context: contextOverride ?? this.context,
      requestId: this.requestId,
      userId: this.userId,
      ...(customContext ?? {}),
    };

    // Filter out undefined values for cleaner output
    Object.keys(contextObj).forEach((key) => {
      if (contextObj[key] === undefined) delete contextObj[key];
    });

    return JSON.stringify(contextObj);
  }
}
