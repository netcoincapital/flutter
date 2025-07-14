package com.laxce.adl.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey

class KeystoreManager {

    private val keyStore: KeyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    fun deleteKey(alias: String) {
        try {
            if (keyStore.containsAlias(alias)) {
                keyStore.deleteEntry(alias)
                Log.d("KeystoreManager", "Alias '$alias' deleted successfully.")
            } else {
                Log.d("KeystoreManager", "Alias '$alias' does not exist.")
            }
        } catch (e: Exception) {
            Log.e("KeystoreManager", "Exception while deleting alias '$alias': ${e.message}", e)
        }
    }

    fun generateKey(alias: String) {
        val keyGenParameterSpec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setKeySize(2048) // اطمینان از اندازه کلید صحیح
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setIsStrongBoxBacked(false) // در صورت عدم نیاز به StrongBox
            .build()

        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            "AndroidKeyStore"
        )
        keyPairGenerator.initialize(keyGenParameterSpec)
        keyPairGenerator.generateKeyPair()
    }

    fun containsAlias(alias: String): Boolean {
        return keyStore.containsAlias(alias)
    }

}


