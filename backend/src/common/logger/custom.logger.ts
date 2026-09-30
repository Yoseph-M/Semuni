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
  [key: string]: any;
}

@Injectable({ scope: Scope.TRANSIENT })
export class CustomLogger extends ConsoleLogger {
  private requestId?: string;
  private userId?: string;

  constructor() {
    super();
  }

  setContext(context: string) {
    super.setContext(context);
  }

  setRequest(request: Request | IncomingMessage) {
    if (request && 'requestId' in request) {
      this.requestId = (request as Request).requestId;
    }
    if (request && 'user' in request && (request as any).user && (request as any).user.sub) {
      this.userId = (request as any).user.sub;
    }
  }

  // Standard signature for log / warn / debug / verbose:
  //   (message, context?, customContext?)
  // For error(), keep Nest's traditional (message, stackTrace?, context?, customContext?)

  log(message: any, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.log(message, enhancedContext);
  }

  error(
    message: any,
    traceOrStack?: string,
    context?: string,
    customContext?: CustomLogContext,
  ) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.error(message, traceOrStack, enhancedContext);
  }

  warn(message: any, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.warn(message, enhancedContext);
  }

  debug(message: any, context?: string, customContext?: CustomLogContext) {
    const enhancedContext = this.getEnhancedContext(customContext, context);
    super.debug(message, enhancedContext);
  }

  verbose(message: any, context?: string, customContext?: CustomLogContext) {
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
