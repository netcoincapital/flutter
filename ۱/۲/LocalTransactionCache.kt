package com.laxce.adl.utility

import androidx.compose.runtime.mutableStateListOf
import com.laxce.adl.api.Transaction
import kotlin.math.abs

object LocalTransactionCache {
    private val _pendingTransactions = mutableStateListOf<Transaction>()
    val pendingTransactions: List<Transaction> get() = _pendingTransactions

    fun add(transaction: Transaction) {
        // اگر pending مشابه وجود دارد، اضافه نکن
        val exists = _pendingTransactions.any {
            it.status?.lowercase() == "pending" &&
            it.to.equals(transaction.to, ignoreCase = true) &&
            it.amount == transaction.amount
        }
        if (!exists) {
            _pendingTransactions.add(0, transaction)
        }
    }

    fun removeById(txHash: String) {
        _pendingTransactions.removeAll { it.txHash == txHash }
    }

    fun clear() {
        _pendingTransactions.clear()
    }

    fun updateById(txHash: String, newTx: Transaction) {
        val index = _pendingTransactions.indexOfFirst { it.txHash == txHash }
        if (index != -1) {
            // حفظ temporaryId هنگام جایگزینی
            val originalTempId = _pendingTransactions[index].temporaryId
            _pendingTransactions[index] = newTx.apply {
                temporaryId = originalTempId
            }
        }
    }

    fun matchAndReplacePending(serverTx: Transaction) {

        // 1. Print all pending transactions for debugging
        if (_pendingTransactions.isNotEmpty()) {
            _pendingTransactions.forEachIndexed { index, tx ->
            }
        } else {
        }

        // 2. match by temporaryId
        val indexByTempId = _pendingTransactions.indexOfFirst {
            it.temporaryId != null && it.temporaryId == serverTx.temporaryId
        }
        if (indexByTempId != -1) {
            _pendingTransactions.removeAt(indexByTempId)
            return
        }

        // 3. match by txHash
        val indexByTxHash = _pendingTransactions.indexOfFirst {
            it.txHash == serverTx.txHash || serverTx.txHash.contains(it.txHash, ignoreCase = true) || it.txHash.contains(serverTx.txHash, ignoreCase = true)
        }
        if (indexByTxHash != -1) {
            _pendingTransactions.removeAt(indexByTxHash)
            return
        }

        // 4. match by fields with less strict comparison
        val indexByFields = _pendingTransactions.indexOfFirst {
            it.status.lowercase() == "pending" && 
            it.tokenSymbol.equals(serverTx.tokenSymbol, ignoreCase = true) &&
            (it.amount == serverTx.amount || 
             abs((it.amount.toDoubleOrNull() ?: 0.0) - (serverTx.amount.toDoubleOrNull() ?: 0.0)) < 0.000001) &&
            it.to.equals(serverTx.to, ignoreCase = true)
        }
        if (indexByFields != -1) {
            _pendingTransactions.removeAt(indexByFields)
            return
        } else {
        }
    }
} 
