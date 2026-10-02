import { NotificationsService, MAX_NOTIFICATION_ATTEMPTS } from './notifications.service';
import { NotificationStatus } from './entities/notification-outbox.entity';

describe('NotificationsService', () => {
  const row = (overrides: Record<string, unknown> = {}) => ({
    id: 'n1',
    userId: 'u1',
    channel: 'PUSH',
    title: 't',
    body: 'b',
    status: NotificationStatus.PENDING,
    attempts: 0,
    nextAttemptAt: new Date(),
    ...overrides,
  });

  const setup = (rows: any[], send: jest.Mock) => {
    const qb: any = {};
    for (const m of ['setLock', 'setOnLocked', 'where', 'andWhere', 'orderBy', 'limit']) {
      qb[m] = jest.fn(() => qb);
    }
    qb.getMany = jest.fn().mockResolvedValue(rows);
    const manager = {
      getRepository: () => ({ createQueryBuilder: () => qb }),
      save: jest.fn(async (x) => x),
      insert: jest.fn(),
    };
    const dataSource = { transaction: (cb: any) => cb(manager) };
    return {
      service: new NotificationsService(dataSource as any, { send }),
      manager,
      qb,
    };
  };

  it('enqueues through the caller’s transaction manager', async () => {
    const { service, manager } = setup([], jest.fn());
    await service.enqueue(manager as any, [{ userId: 'u1', title: 't', body: 'b' }]);
    expect(manager.insert).toHaveBeenCalledWith(expect.anything(), [
      expect.objectContaining({ userId: 'u1', channel: 'PUSH' }),
    ]);
  });

  it('marks delivered rows SENT and skips rows locked by another dispatcher', async () => {
    const r = row();
    const { service, qb } = setup([r], jest.fn().mockResolvedValue(undefined));
    await expect(service.dispatchPending()).resolves.toEqual({ sent: 1, retrying: 0, failed: 0 });
    expect(r.status).toBe(NotificationStatus.SENT);
    expect(qb.setOnLocked).toHaveBeenCalledWith('skip_locked');
  });

  it('backs off on failure and gives up after the max attempts', async () => {
    const retry = row({ id: 'a' });
    const last = row({ id: 'b', attempts: MAX_NOTIFICATION_ATTEMPTS - 1 });
    const { service } = setup([retry, last], jest.fn().mockRejectedValue(new Error('down')));
    await expect(service.dispatchPending()).resolves.toEqual({ sent: 0, retrying: 1, failed: 1 });
    expect(retry.status).toBe(NotificationStatus.PENDING);
    expect((retry.nextAttemptAt as Date).getTime()).toBeGreaterThan(Date.now());
    expect(last.status).toBe(NotificationStatus.FAILED);
    expect((last as any).lastError).toBe('down');
  });
});
