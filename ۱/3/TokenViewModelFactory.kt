package com.laxce.adl.factories

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.laxce.adl.viewmodel.token_view_model

class TokenViewModelFactory(
    private val context: Context,
    private val userId: String  // اضافه کردن userId به constructor
) : ViewModelProvider.Factory {

    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(token_view_model::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return token_view_model(context, userId) as T // ارسال userId
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
