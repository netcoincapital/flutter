# Backend Integration for Transaction Notifications

این راهنما نحوه پیاده‌سازی backend برای ارسال push notifications هنگام confirm شدن transactions را توضیح می‌دهد.

## 📋 مراحل پیاده‌سازی

### 1. Firebase Admin SDK Setup

#### Node.js Backend:
```bash
npm install firebase-admin
```

```javascript
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./path/to/service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});
```

#### Python Backend:
```bash
pip install firebase-admin
```

```python
import firebase_admin
from firebase_admin import credentials, messaging

# Initialize Firebase Admin
cred = credentials.Certificate("path/to/service-account-key.json")
firebase_admin.initialize_app(cred)
```

### 2. FCM Token Registration API

Backend باید endpoint برای ثبت FCM tokens داشته باشد:

#### Node.js Express:
```javascript
app.post('/api/register-fcm-token', async (req, res) => {
  try {
    const { userId, fcmToken, platform } = req.body;
    
    // Save to database
    await db.collection('users').doc(userId).update({
      fcmToken: fcmToken,
      platform: platform,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    res.status(200).json({ success: true });
  } catch (error) {
    console.error('Error registering FCM token:', error);
    res.status(500).json({ error: error.message });
  }
});
```

#### Python Flask:
```python
@app.route('/api/register-fcm-token', methods=['POST'])
def register_fcm_token():
    try:
        data = request.get_json()
        user_id = data['userId']
        fcm_token = data['fcmToken']
        platform = data['platform']
        
        # Save to database
        db.collection('users').document(user_id).update({
            'fcmToken': fcm_token,
            'platform': platform,
            'updatedAt': firestore.SERVER_TIMESTAMP
        })
        
        return {'success': True}, 200
    except Exception as e:
        return {'error': str(e)}, 500
```

### 3. Transaction Notification Function

هنگام confirm شدن transaction، notification ارسال کنید:

#### Node.js:
```javascript
async function sendTransactionNotification(userId, transactionData) {
  try {
    // Get user's FCM token
    const userDoc = await db.collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;
    
    if (!fcmToken) {
      console.log('No FCM token found for user:', userId);
      return;
    }
    
    // Prepare notification
    const message = {
      notification: {
        title: 'Transaction Confirmed',
        body: `Your transaction of ${transactionData.amount} ${transactionData.symbol} has been confirmed`
      },
      data: {
        type: 'transaction',
        transactionId: transactionData.id,
        hash: transactionData.hash,
        amount: transactionData.amount.toString(),
        symbol: transactionData.symbol,
        explorerUrl: transactionData.explorerUrl,
        action: 'view_transaction'
      },
      token: fcmToken,
      android: {
        notification: {
          icon: 'ic_notification',
          color: '#16B369'
        }
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default'
          }
        }
      }
    };
    
    // Send notification
    const response = await admin.messaging().send(message);
    console.log('Successfully sent notification:', response);
    
  } catch (error) {
    console.error('Error sending transaction notification:', error);
  }
}

// Usage when transaction is confirmed
app.post('/api/transaction-confirmed', async (req, res) => {
  const { userId, transactionData } = req.body;
  
  // Update transaction status in database
  await updateTransactionStatus(transactionData.id, 'confirmed');
  
  // Send notification
  await sendTransactionNotification(userId, transactionData);
  
  res.status(200).json({ success: true });
});
```

#### Python:
```python
def send_transaction_notification(user_id, transaction_data):
    try:
        # Get user's FCM token
        user_doc = db.collection('users').document(user_id).get()
        if not user_doc.exists:
            print(f'User not found: {user_id}')
            return
            
        user_data = user_doc.to_dict()
        fcm_token = user_data.get('fcmToken')
        
        if not fcm_token:
            print(f'No FCM token found for user: {user_id}')
            return
        
        # Prepare notification
        message = messaging.Message(
            notification=messaging.Notification(
                title='Transaction Confirmed',
                body=f"Your transaction of {transaction_data['amount']} {transaction_data['symbol']} has been confirmed"
            ),
            data={
                'type': 'transaction',
                'transactionId': transaction_data['id'],
                'hash': transaction_data['hash'],
                'amount': str(transaction_data['amount']),
                'symbol': transaction_data['symbol'],
                'explorerUrl': transaction_data['explorerUrl'],
                'action': 'view_transaction'
            },
            token=fcm_token,
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(
                    icon='ic_notification',
                    color='#16B369'
                )
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(badge=1, sound='default')
                )
            )
        )
        
        # Send notification
        response = messaging.send(message)
        print(f'Successfully sent notification: {response}')
        
    except Exception as e:
        print(f'Error sending transaction notification: {e}')

@app.route('/api/transaction-confirmed', methods=['POST'])
def transaction_confirmed():
    data = request.get_json()
    user_id = data['userId']
    transaction_data = data['transactionData']
    
    # Update transaction status in database
    update_transaction_status(transaction_data['id'], 'confirmed')
    
    # Send notification
    send_transaction_notification(user_id, transaction_data)
    
    return {'success': True}, 200
```

### 4. Flutter App Integration

App باید FCM token را backend ارسال کند:

```dart
// در فایل lib/services/api_service.dart
class ApiService {
  Future<bool> registerFCMToken(String userId, String fcmToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/register-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'fcmToken': fcmToken,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Error registering FCM token: $e');
      return false;
    }
  }
}
```

### 5. Transaction Monitoring

Backend باید transactions را monitor کند:

```javascript
// Monitor blockchain for transaction confirmations
async function monitorTransactions() {
  const pendingTransactions = await db.collection('transactions')
    .where('status', '==', 'pending')
    .get();
    
  for (const doc of pendingTransactions.docs) {
    const transaction = doc.data();
    
    // Check transaction status on blockchain
    const isConfirmed = await checkTransactionOnBlockchain(
      transaction.hash, 
      transaction.network
    );
    
    if (isConfirmed) {
      // Update status
      await doc.ref.update({ 
        status: 'confirmed',
        confirmedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      // Send notification
      await sendTransactionNotification(transaction.userId, transaction);
    }
  }
}

// Run every 30 seconds
setInterval(monitorTransactions, 30000);
```

### 6. Different Notification Types

```javascript
// Security Alert
const securityMessage = {
  notification: {
    title: 'Security Alert',
    body: 'New device login detected'
  },
  data: {
    type: 'security',
    action: 'view_security'
  },
  token: fcmToken
};

// Price Alert
const priceMessage = {
  notification: {
    title: 'Price Alert',
    body: `${symbol} reached your target price of $${targetPrice}`
  },
  data: {
    type: 'price',
    symbol: symbol,
    price: currentPrice.toString(),
    action: 'view_chart'
  },
  token: fcmToken
};

// Balance Update
const balanceMessage = {
  notification: {
    title: 'Balance Updated',
    body: `You received ${amount} ${symbol}`
  },
  data: {
    type: 'balance',
    symbol: symbol,
    amount: amount.toString(),
    action: 'view_wallet'
  },
  token: fcmToken
};
```

### 7. Error Handling

```javascript
async function sendNotificationWithRetry(message, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const response = await admin.messaging().send(message);
      console.log(`Notification sent successfully: ${response}`);
      return response;
    } catch (error) {
      console.error(`Attempt ${attempt} failed:`, error.message);
      
      if (error.code === 'messaging/registration-token-not-registered') {
        // Token is invalid, remove from database
        await removeInvalidToken(message.token);
        break;
      }
      
      if (attempt === maxRetries) {
        throw error;
      }
      
      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
    }
  }
}
```

### 8. Testing

```bash
# Test notification endpoint
curl -X POST http://localhost:3000/api/send-test-notification \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test_user_id",
    "title": "Test Notification",
    "body": "This is a test notification",
    "data": {
      "type": "test",
      "action": "none"
    }
  }'
```

### 9. Environment Variables

```bash
# .env file
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY_ID=your-private-key-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com
FIREBASE_CLIENT_ID=123456789012345678901
FIREBASE_AUTH_URI=https://accounts.google.com/o/oauth2/auth
FIREBASE_TOKEN_URI=https://oauth2.googleapis.com/token
```

### 10. Production Considerations

1. **Rate Limiting**: FCM has rate limits, implement queuing
2. **Token Cleanup**: Remove invalid tokens from database
3. **Monitoring**: Log notification success/failure rates
4. **Personalization**: Send notifications in user's preferred language
5. **Scheduling**: Use job queues for reliable delivery
6. **Analytics**: Track notification open rates

---

## Quick Start Checklist

- [ ] Firebase project created
- [ ] Service account key downloaded
- [ ] Backend FCM registration endpoint implemented
- [ ] Transaction monitoring system setup
- [ ] Notification sending function implemented
- [ ] App FCM token registration working
- [ ] Test notifications sent successfully
- [ ] Production deployment completed

---

برای شروع سریع، ابتدا Firebase project setup کنید و سپس test notification از Firebase Console ارسال کنید. 