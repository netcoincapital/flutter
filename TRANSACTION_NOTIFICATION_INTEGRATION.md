# Transaction Notification Integration Guide

این راهنما نحوه پیاده‌سازی خودکار push notifications برای transaction events را توضیح می‌دهد.

## 🎯 مشکل فعلی

**چرا هنگام transaction، notification نمی‌آید؟**

```
User Transaction --> Backend API --> Database --> ❌ NO NOTIFICATION
```

**باید این طور باشد:**

```
User Transaction --> Backend API --> Database --> FCM Service --> Push Notification
```

## 📋 مراحل پیاده‌سازی

### 1. Transaction Event Detection

Backend باید transaction events را detect کند:

#### در API Transaction Endpoint:
```javascript
// Node.js Express
app.post('/api/send-transaction', async (req, res) => {
  try {
    const { userId, from, to, amount, symbol, network } = req.body;
    
    // Send transaction to blockchain
    const transactionHash = await sendToBlockchain(req.body);
    
    // Save to database
    const transaction = await db.collection('transactions').add({
      userId,
      hash: transactionHash,
      from,
      to,
      amount,
      symbol,
      network,
      status: 'pending',
      createdAt: new Date(),
    });
    
    // 🚀 IMMEDIATELY send "pending" notification
    await sendTransactionNotification(userId, {
      id: transaction.id,
      hash: transactionHash,
      amount,
      symbol,
      status: 'pending',
      type: 'sent'
    });
    
    res.json({ 
      success: true, 
      transactionId: transaction.id,
      hash: transactionHash 
    });
    
  } catch (error) {
    console.error('Transaction failed:', error);
    res.status(500).json({ error: error.message });
  }
});
```

#### Python Flask:
```python
@app.route('/api/send-transaction', methods=['POST'])
def send_transaction():
    try:
        data = request.get_json()
        user_id = data['userId']
        
        # Send to blockchain
        tx_hash = send_to_blockchain(data)
        
        # Save to database
        transaction = {
            'userId': user_id,
            'hash': tx_hash,
            'amount': data['amount'],
            'symbol': data['symbol'],
            'status': 'pending',
            'createdAt': datetime.now()
        }
        
        tx_ref = db.collection('transactions').add(transaction)
        
        # 🚀 Send notification immediately
        send_transaction_notification(user_id, {
            'id': tx_ref[1].id,
            'hash': tx_hash,
            'amount': data['amount'],
            'symbol': data['symbol'],
            'status': 'pending',
            'type': 'sent'
        })
        
        return {'success': True, 'transactionId': tx_ref[1].id, 'hash': tx_hash}
        
    except Exception as e:
        return {'error': str(e)}, 500
```

### 2. Transaction Monitoring System

برای track کردن pending transactions:

#### Node.js Monitoring:
```javascript
const monitorTransactions = async () => {
  console.log('🔍 Checking pending transactions...');
  
  try {
    // Get all pending transactions
    const pendingTxs = await db.collection('transactions')
      .where('status', '==', 'pending')
      .where('createdAt', '>', new Date(Date.now() - 24 * 60 * 60 * 1000)) // Last 24 hours
      .get();
    
    for (const doc of pendingTxs.docs) {
      const tx = doc.data();
      
      try {
        // Check transaction status on blockchain
        const receipt = await checkTransactionStatus(tx.hash, tx.network);
        
        if (receipt && receipt.status === 'success') {
          // Update status in database
          await doc.ref.update({
            status: 'confirmed',
            confirmedAt: new Date(),
            blockNumber: receipt.blockNumber,
            gasUsed: receipt.gasUsed
          });
          
          // 🎉 Send confirmation notification
          await sendTransactionNotification(tx.userId, {
            id: doc.id,
            hash: tx.hash,
            amount: tx.amount,
            symbol: tx.symbol,
            status: 'confirmed',
            type: tx.type || 'transaction',
            explorerUrl: getExplorerUrl(tx.hash, tx.network)
          });
          
          console.log(`✅ Transaction confirmed: ${tx.hash}`);
          
        } else if (receipt && receipt.status === 'failed') {
          // Update as failed
          await doc.ref.update({
            status: 'failed',
            failedAt: new Date(),
            error: receipt.error
          });
          
          // Send failure notification
          await sendTransactionNotification(tx.userId, {
            id: doc.id,
            hash: tx.hash,
            amount: tx.amount,
            symbol: tx.symbol,
            status: 'failed',
            type: 'transaction'
          });
          
          console.log(`❌ Transaction failed: ${tx.hash}`);
        }
        
      } catch (error) {
        console.error(`Error checking transaction ${tx.hash}:`, error);
      }
    }
    
  } catch (error) {
    console.error('Error in transaction monitoring:', error);
  }
};

// Run every 30 seconds
setInterval(monitorTransactions, 30 * 1000);
```

### 3. Blockchain Status Checker

```javascript
const checkTransactionStatus = async (hash, network) => {
  try {
    let provider;
    
    switch (network.toLowerCase()) {
      case 'ethereum':
        provider = new ethers.providers.JsonRpcProvider(process.env.ETHEREUM_RPC_URL);
        break;
      case 'polygon':
        provider = new ethers.providers.JsonRpcProvider(process.env.POLYGON_RPC_URL);
        break;
      case 'bsc':
        provider = new ethers.providers.JsonRpcProvider(process.env.BSC_RPC_URL);
        break;
      default:
        throw new Error(`Unsupported network: ${network}`);
    }
    
    const receipt = await provider.getTransactionReceipt(hash);
    
    if (receipt) {
      return {
        status: receipt.status === 1 ? 'success' : 'failed',
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        confirmations: await provider.getBlockNumber() - receipt.blockNumber
      };
    }
    
    return null; // Still pending
    
  } catch (error) {
    console.error(`Error checking transaction status:`, error);
    return null;
  }
};
```

### 4. Enhanced Notification Function

```javascript
const sendTransactionNotification = async (userId, transactionData) => {
  try {
    // Get user's FCM token
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data();
    
    if (!userData?.fcmToken) {
      console.log(`No FCM token for user: ${userId}`);
      return;
    }
    
    const { fcmToken } = userData;
    const { id, hash, amount, symbol, status, type, explorerUrl } = transactionData;
    
    // Determine notification content based on status
    let title, body, icon, color;
    
    switch (status) {
      case 'pending':
        title = 'Transaction Sent';
        body = `Your ${amount} ${symbol} transfer is being processed...`;
        icon = 'ic_pending';
        color = '#FF9500';
        break;
        
      case 'confirmed':
        title = 'Transaction Confirmed ✅';
        body = `Your ${amount} ${symbol} transfer has been confirmed!`;
        icon = 'ic_success';
        color = '#16B369';
        break;
        
      case 'failed':
        title = 'Transaction Failed ❌';
        body = `Your ${amount} ${symbol} transfer failed. Please try again.`;
        icon = 'ic_error';
        color = '#DC0303';
        break;
        
      case 'received':
        title = 'Received Crypto 💰';
        body = `You received ${amount} ${symbol}`;
        icon = 'ic_received';
        color = '#16B369';
        break;
        
      default:
        title = 'Transaction Update';
        body = `${amount} ${symbol} - Status: ${status}`;
        icon = 'ic_transaction';
        color = '#16B369';
    }
    
    // Prepare FCM message
    const message = {
      notification: {
        title,
        body
      },
      data: {
        type: 'transaction',
        transactionId: id,
        hash: hash,
        amount: amount.toString(),
        symbol: symbol,
        status: status,
        action: 'view_transaction',
        explorerUrl: explorerUrl || '',
        timestamp: new Date().toISOString()
      },
      token: fcmToken,
      android: {
        notification: {
          icon: icon,
          color: color,
          sound: 'default',
          priority: 'high'
        }
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'content-available': 1
          }
        }
      }
    };
    
    // Send notification
    const response = await admin.messaging().send(message);
    console.log(`✅ Notification sent to ${userId}:`, response);
    
    // Log notification to database
    await db.collection('notifications').add({
      userId,
      transactionId: id,
      type: 'transaction',
      title,
      body,
      status: 'sent',
      fcmResponse: response,
      sentAt: new Date()
    });
    
  } catch (error) {
    console.error('Error sending transaction notification:', error);
    
    // Log failed notification
    await db.collection('notifications').add({
      userId,
      transactionId: transactionData.id,
      type: 'transaction',
      status: 'failed',
      error: error.message,
      sentAt: new Date()
    });
  }
};
```

### 5. Incoming Transaction Detection

برای detect کردن incoming transactions:

```javascript
const monitorIncomingTransactions = async () => {
  try {
    // Get all user wallets
    const users = await db.collection('users').get();
    
    for (const userDoc of users.docs) {
      const userData = userDoc.data();
      const { walletAddresses } = userData;
      
      if (!walletAddresses) continue;
      
      for (const address of walletAddresses) {
        // Check for new incoming transactions
        const latestBlock = await getLatestBlock(address.network);
        const lastChecked = userData.lastBlockChecked?.[address.network] || 0;
        
        if (latestBlock > lastChecked) {
          const newTxs = await getTransactionHistory(
            address.address, 
            address.network, 
            lastChecked + 1
          );
          
          for (const tx of newTxs) {
            if (tx.to.toLowerCase() === address.address.toLowerCase() && tx.value > 0) {
              // This is an incoming transaction
              await saveIncomingTransaction(userDoc.id, tx);
              
              // Send notification
              await sendTransactionNotification(userDoc.id, {
                id: tx.hash,
                hash: tx.hash,
                amount: tx.value,
                symbol: tx.symbol || 'ETH',
                status: 'received',
                type: 'received',
                explorerUrl: getExplorerUrl(tx.hash, address.network)
              });
            }
          }
          
          // Update last checked block
          await userDoc.ref.update({
            [`lastBlockChecked.${address.network}`]: latestBlock
          });
        }
      }
    }
    
  } catch (error) {
    console.error('Error monitoring incoming transactions:', error);
  }
};

// Run every 2 minutes for incoming transactions
setInterval(monitorIncomingTransactions, 2 * 60 * 1000);
```

### 6. Flutter App Integration

در اپ Flutter، باید transaction events را backend ارسال کنید:

```dart
// در فایل transaction service
class TransactionService {
  
  Future<String> sendTransaction({
    required String from,
    required String to,
    required double amount,
    required String symbol,
    required String network,
  }) async {
    try {
      // Send transaction to backend
      final response = await ApiService().sendTransaction(
        from: from,
        to: to,
        amount: amount,
        symbol: symbol,
        network: network,
      );
      
      if (response.success) {
        print('✅ Transaction sent, notification will follow');
        return response.transactionHash;
      } else {
        throw Exception('Transaction failed');
      }
      
    } catch (e) {
      print('❌ Transaction error: $e');
      rethrow;
    }
  }
}
```

### 7. Testing Transaction Notifications

```bash
# Test transaction notification
curl -X POST http://localhost:3000/api/test-transaction-notification \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test_user_123",
    "transactionData": {
      "id": "tx_test_001",
      "hash": "0x1234567890abcdef...",
      "amount": "0.5",
      "symbol": "ETH",
      "status": "confirmed",
      "type": "sent"
    }
  }'
```

### 8. Environment Configuration

```bash
# .env file
FIREBASE_PROJECT_ID=laxce-wallet
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@laxce-wallet.iam.gserviceaccount.com

# Blockchain RPC URLs
ETHEREUM_RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
POLYGON_RPC_URL=https://polygon-mainnet.infura.io/v3/YOUR_PROJECT_ID
BSC_RPC_URL=https://bsc-dataseed.binance.org/

# Notification settings
NOTIFICATION_CHECK_INTERVAL=30000
INCOMING_TX_CHECK_INTERVAL=120000
```

## 🚀 Quick Implementation Steps

### Day 1: Setup Firebase
1. Create Firebase project
2. Setup FCM in backend
3. Test manual notifications

### Day 2: Transaction Events
1. Add notification calls to transaction endpoints
2. Test sent transaction notifications

### Day 3: Monitoring System
1. Implement transaction status monitoring
2. Test confirmation notifications

### Day 4: Incoming Transactions
1. Setup wallet monitoring
2. Test incoming transaction notifications

### Day 5: Production
1. Deploy and monitor
2. Optimize performance
3. Add analytics

## 📊 Expected Results

After implementation:

```
✅ User sends crypto → Immediate "Transaction Sent" notification
✅ Transaction confirms → "Transaction Confirmed" notification  
✅ User receives crypto → "Received Crypto" notification
✅ Transaction fails → "Transaction Failed" notification
```

## 🔧 Troubleshooting

**No notifications received:**
1. Check FCM token registration
2. Verify Firebase credentials
3. Check backend logs
4. Test with Firebase Console

**Delayed notifications:**
1. Reduce monitoring intervals
2. Optimize blockchain queries
3. Use webhooks instead of polling

**Missing transactions:**
1. Check wallet address registration
2. Verify network configurations
3. Monitor RPC endpoint status 