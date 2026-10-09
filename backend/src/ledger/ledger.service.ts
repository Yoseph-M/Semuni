import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, EntityManager } from 'typeorm';
import { LedgerEntry } from './entities/ledger-entry.entity';
import {
  LedgerDirection,
  LedgerEntryType,
  Currency,
} from '../common/enums';

@Injectable()
export class LedgerService {
  constructor(
    @InjectRepository(LedgerEntry)
    private readonly ledgerEntryRepository: Repository<LedgerEntry>,
  ) {}

  async recordEntry(
    manager: EntityManager,
    data: {
      walletId: string;
      transactionId?: string;
      entryType: LedgerEntryType;
      direction: LedgerDirection;
      amount: number;
      currency?: Currency;
      balanceBefore: number;
      balanceAfter: number;
      referenceType?: string;
      referenceId?: string;
      description?: string;
    },
  ): Promise<LedgerEntry> {
    const entry = manager.create(LedgerEntry, {
      walletId: data.walletId,
      transactionId: data.transactionId,
      entryType: data.entryType,
      direction: data.direction,
      amount: data.amount,
      currency: data.currency || Currency.ETB,
      balanceBefore: data.balanceBefore,
      balanceAfter: data.balanceAfter,
      referenceType: data.referenceType,
      referenceId: data.referenceId,
      description: data.description,
    });

    return manager.save(entry);
  }

  async getEntriesByWalletId(
    walletId: string,
    limit = 50,
  ): Promise<LedgerEntry[]> {
    return this.ledgerEntryRepository.find({
      where: { walletId },
      order: { createdAt: 'DESC' },
      take: limit,
    });
  }

  async findByReference(
    referenceType: string,
    referenceId: string,
  ): Promise<LedgerEntry | null> {
    return this.ledgerEntryRepository.findOne({
      where: { referenceType, referenceId },
    });
  }
}
