package com.laxce.adl.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.laxce.adl.viewmodel.HistoryViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStoreOwner

class TransactionNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "TRANSACTION_CONFIRMED" -> {
                val transactionId = intent.getStringExtra("transaction_id")
                if (transactionId != null) {
                    // Get the ViewModel instance
                    val viewModelStoreOwner = context as? ViewModelStoreOwner
                    if (viewModelStoreOwner != null) {
                        val viewModel = ViewModelProvider(viewModelStoreOwner)[HistoryViewModel::class.java]
                        viewModel.removePendingTransaction(transactionId)
                    }
                }
            }
        }
    }
} 
