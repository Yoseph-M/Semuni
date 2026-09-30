import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const headerRequestId = req.headers['x-request-id'];
    const requestId =
      (Array.isArray(headerRequestId) ? headerRequestId[0] : headerRequestId) ||
      uuidv4();
    req['requestId'] = requestId; // Attach to request object
    res.setHeader('X-Request-ID', requestId); // Set header for traceability
    next();
  }
}
