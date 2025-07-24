#!/usr/bin/env python3
"""
Quick Firebase Cloud Messaging Test Script
برای تست سریع push notifications

Usage:
1. Install: pip install firebase-admin
2. Get FCM token from app
3. Run: python test_notification.py [FCM_TOKEN]
"""

import sys
import json
from datetime import datetime

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:
    print("❌ Error: firebase-admin not installed")
    print("📦 Install with: pip install firebase-admin")
    sys.exit(1)

def send_test_notification(fcm_token):
    """Send a test notification to the given FCM token"""
    
    # Note: You need a real service account key for this to work
    # For now, this is just a template
    print("🔥 Firebase Test Notification Sender")
    print("=" * 50)
    
    try:
        # Initialize Firebase (you need real credentials)
        """
        # Uncomment when you have real credentials:
        cred = credentials.Certificate("path/to/service-account-key.json")
        firebase_admin.initialize_app(cred)
        
        # Prepare test message
        message = messaging.Message(
            notification=messaging.Notification(
                title='🎉 Test Notification',
                body='Your Laxce Wallet notifications are working!'
            ),
            data={
                'type': 'test',
                'timestamp': datetime.now().isoformat(),
                'action': 'none'
            },
            token=fcm_token,
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(
                    icon='ic_notification',
                    color='#16B369',
                    sound='default'
                )
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        badge=1,
                        sound='default'
                    )
                )
            )
        )
        
        # Send notification
        response = messaging.send(message)
        print(f'✅ Successfully sent notification: {response}')
        """
        
        print("⚠️ Template script - requires real Firebase credentials")
        print("📍 Steps to make this work:")
        print("1. Create Firebase project")
        print("2. Download service account key JSON")
        print("3. Update script with real credentials")
        print("4. Run with your FCM token")
        print()
        print(f"🪙 Your FCM Token: {fcm_token}")
        print()
        print("🔗 Alternative: Use Firebase Console")
        print("   • Go to: https://console.firebase.google.com/")
        print("   • Cloud Messaging → Send your first message")
        print("   • Target: Single device")
        print("   • Token:", fcm_token[:20] + "...")
        
    except Exception as e:
        print(f"❌ Error: {e}")

def send_transaction_test(fcm_token):
    """Send a test transaction notification"""
    
    print("📱 Transaction Notification Test")
    print("=" * 50)
    
    # Sample transaction data
    sample_transaction = {
        'type': 'transaction',
        'title': 'Transaction Confirmed ✅',
        'body': 'Your transfer of 0.5 ETH has been confirmed on Ethereum network',
        'data': {
            'type': 'transaction',
            'transactionId': 'tx_123456789',
            'hash': '0x1234567890abcdef...',
            'amount': '0.5',
            'symbol': 'ETH',
            'network': 'ethereum',
            'explorerUrl': 'https://etherscan.io/tx/0x1234567890abcdef...',
            'action': 'view_transaction',
            'timestamp': datetime.now().isoformat()
        }
    }
    
    print("📋 Notification payload:")
    print(json.dumps(sample_transaction, indent=2))
    print()
    print(f"🪙 Target FCM Token: {fcm_token[:20]}...")
    print()
    print("💡 To send this notification:")
    print("1. Use Firebase Console Cloud Messaging")
    print("2. Copy the payload above to 'Additional options → Custom data'")
    print("3. Set title and body from the payload")
    print("4. Send to single device with your FCM token")

def main():
    """Main function"""
    
    print("🚀 Laxce Wallet - FCM Notification Tester")
    print("=" * 60)
    
    if len(sys.argv) < 2:
        print("❌ Usage: python test_notification.py [FCM_TOKEN]")
        print()
        print("📱 To get your FCM token:")
        print("1. Open Laxce Wallet app")
        print("2. Go to Settings → Notifications")
        print("3. Tap 'Enable Notifications'")
        print("4. Tap 'Check Status'")
        print("5. Copy the FCM token")
        print()
        print("Example:")
        print("python test_notification.py fGcK7-8xSr2Vn...")
        sys.exit(1)
    
    fcm_token = sys.argv[1]
    
    if len(fcm_token) < 50:
        print("⚠️ Warning: FCM token seems too short")
        print("   Make sure you copied the complete token")
    
    print(f"🪙 FCM Token: {fcm_token[:30]}...")
    print()
    
    # Test options
    print("📋 Available tests:")
    print("1. Basic test notification")
    print("2. Transaction notification test")
    print("3. Show Firebase Console instructions")
    print()
    
    choice = input("Select test type (1-3): ").strip()
    
    if choice == "1":
        send_test_notification(fcm_token)
    elif choice == "2":
        send_transaction_test(fcm_token)
    elif choice == "3":
        print()
        print("🔗 Firebase Console Steps:")
        print("=" * 40)
        print("1. Go to: https://console.firebase.google.com/")
        print("2. Select your Laxce Wallet project")
        print("3. Cloud Messaging → 'Send your first message'")
        print("4. Enter notification title and body")
        print("5. Target: 'Single device'")
        print(f"6. FCM registration token: {fcm_token}")
        print("7. Click 'Send'")
        print()
        print("📋 Test notification content:")
        print("Title: Transaction Confirmed")
        print("Body: Your 0.5 ETH transfer was successful!")
    else:
        print("❌ Invalid choice")

if __name__ == "__main__":
    main() 