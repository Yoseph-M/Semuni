import {
  CallHandler,
  ExecutionContext,
  HttpException,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Observable, tap } from 'rxjs';
import { Repository } from 'typeorm';
import { AuditLog } from './entities/audit-log.entity';

const MUTATING = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

interface AuditedRequest {
  method: string;
  url: string;
  ip?: string;
  headers: Record<string, string | string[] | undefined>;
  params?: Record<string, string>;
  routeOptions?: { url?: string };
  user?: { id?: string; sub?: string; role?: string };
  requestId?: string;
  raw?: { requestId?: string };
}

/**
 * Records who changed what (route pattern, actor, outcome) for every mutating
 * request, successful or not. Bodies are never stored (passwords, PII).
 * Writing the record is best-effort and never affects the response.
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditInterceptor.name);

  constructor(
    @InjectRepository(AuditLog) private readonly auditRepo: Repository<AuditLog>,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();
    const http = context.switchToHttp();
    const req = http.getRequest<AuditedRequest>();
    if (!MUTATING.has(req.method)) return next.handle();

    return next.handle().pipe(
      tap({
        next: () =>
          this.record(req, http.getResponse<{ statusCode?: number }>().statusCode ?? 200),
        error: (err: unknown) =>
          this.record(req, err instanceof HttpException ? err.getStatus() : 500),
      }),
    );
  }

  private record(req: AuditedRequest, statusCode: number): void {
    const header = req.headers['x-request-id'];
    const entry = this.auditRepo.create({
      actorUserId: req.user?.id ?? req.user?.sub,
      actorRole: req.user?.role,
      action: `${req.method} ${req.routeOptions?.url ?? req.url.split('?')[0]}`.slice(0, 200),
      resourceId: (req.params?.id ?? req.params?.intentId)?.slice(0, 64),
      statusCode,
      requestId: (req.requestId ?? req.raw?.requestId ?? (Array.isArray(header) ? header[0] : header))?.slice(0, 64),
      ip: req.ip?.slice(0, 64),
    });
    this.auditRepo.insert(entry).catch((err: Error) => {
      this.logger.error(`Audit write failed: ${err.message}`);
    });
  }
}
