import '../models/transaction.dart';

class LocalTransactionCache {
  static final List<Transaction> _pendingTransactions = [];
  static final Map<String, Transaction> _transactionMap = {};

  static List<Transaction> get pendingTransactions => List.unmodifiable(_pendingTransactions);

  static void addPendingTransaction(Transaction transaction) {
    _pendingTransactions.add(transaction);
  }

  static void updateById(String txHash, Transaction transaction) {
    _transactionMap[txHash] = transaction;
  }

  static void matchAndReplacePending(Transaction serverTransaction) {
    final index = _pendingTransactions.indexWhere((tx) => tx.txHash == serverTransaction.txHash);
    if (index != -1) {
      _pendingTransactions[index] = serverTransaction;
    }
  }

  static void clearPendingTransactions() {
    _pendingTransactions.clear();
  }

  static void clearAll() {
    _pendingTransactions.clear();
    _transactionMap.clear();
  }
} 