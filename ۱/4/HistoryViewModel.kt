package com.laxce.adl.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.laxce.adl.api.Transaction
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.SharingStarted

class HistoryViewModel : ViewModel() {
    private val _pendingTransactions = MutableStateFlow<List<Transaction>>(emptyList())
    private val _transactionsFromServer = MutableStateFlow<List<Transaction>>(emptyList())

    val pendingTransactions: StateFlow<List<Transaction>> = _pendingTransactions.asStateFlow()
    val transactionsFromServer: StateFlow<List<Transaction>> = _transactionsFromServer.asStateFlow()

    val allTransactions: StateFlow<List<Transaction>> = combine(
        pendingTransactions,
        transactionsFromServer
    ) { pending, server ->
        (pending + server).sortedByDescending { it.timestamp }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList()
    )

    fun addPendingTransaction(transaction: Transaction) {
        viewModelScope.launch {
            _pendingTransactions.value = _pendingTransactions.value + transaction
        }
    }

    fun removePendingTransaction(transactionId: String) {
        viewModelScope.launch {
            _pendingTransactions.value = _pendingTransactions.value.filter { it.txHash != transactionId }
        }
    }

    fun updateServerTransactions(transactions: List<Transaction>) {
        viewModelScope.launch {
            _transactionsFromServer.value = transactions
        }
    }
} 
