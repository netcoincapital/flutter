#!/usr/bin/env python3
"""
Test FCM with Firebase Admin SDK (using Service Account)
"""

import json
from pathlib import Path

# Service Account path (adjust if needed)
service_account_path = Path(__file__).parent / 'coinceeper-f2eaf-firebase-adminsdk-fbsvc-4f2bc9645c.json'

# Device data from database
DEVICE_TOKEN = "euYtawyFT86uVvt5L7shsS:APA91bHoic-emX8mYJNj4-l5MDz6DEA1v0IPdf0x5ri0EWlwvL6SZBnulgzCcd3pSrsOIUOCkOHAT7QNKyrMWdEhd7W-7466vzZ740lDRT9iNf0sDa7pP38"
USER_ID = "2a272775-17e9-4739-a756-67da1090dbcb"
WALLET_ID = "c2569417-736b-4352-860f-5f063948b6b1"

def test_with_admin_sdk():
    """Test with Firebase Admin SDK"""
    
    if not service_account_path.exists():
        print(f"❌ Service account file not found: {service_account_path}")
        print("💡 Please put the JSON file in the same directory as this script")
        return
    
    try:
        # Try to import firebase_admin
        import firebase_admin
        from firebase_admin import credentials, messaging
        print("✅ Firebase Admin SDK imported successfully")
        
    except ImportError:
        print("❌ Firebase Admin SDK not installed")
        print("💡 Install with: pip install firebase-admin")
        return
    
    try:
        # Initialize Firebase Admin
        cred = credentials.Certificate(str(service_account_path))
        
        # Check if already initialized
        try:
            app = firebase_admin.get_app()
            print("✅ Firebase Admin already initialized")
        except ValueError:
            app = firebase_admin.initialize_app(cred)
            print("✅ Firebase Admin initialized successfully")
        
        # Create message
        message = messaging.Message(
            notification=messaging.Notification(
                title="💰 Transaction Received (Admin SDK)",
                body="You received 0.001 BTC via Admin SDK",
            ),
            data={
                "transaction_id": f"admin_test_{int(__import__('time').time())}",
                "type": "receive",
                "amount": "0.001",
                "currency": "BTC",
                "user_id": USER_ID,
                "wallet_id": WALLET_ID,
            },
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(
                    channel_id="receive_channel",
                    sound="receive_sound",
                    priority=messaging.Priority.HIGH,
                )
            ),
            token=DEVICE_TOKEN
        )
        
        print("🚀 Sending notification via Firebase Admin SDK...")
        print(f"📱 Device Token: {DEVICE_TOKEN[:30]}...")
        
        # Send message
        response = messaging.send(message)
        print(f"✅ Message sent successfully! Message ID: {response}")
        print("📱 Check your Android device for the notification")
        
    except Exception as e:
        print(f"❌ Admin SDK Error: {e}")
        print(f"❌ Error type: {type(e).__name__}")

def check_service_account():
    """Check service account file"""
    if service_account_path.exists():
        try:
            with open(service_account_path, 'r') as f:
                data = json.load(f)
            
            print("✅ Service account file found and valid")
            print(f"   Project ID: {data.get('project_id', 'N/A')}")
            print(f"   Client Email: {data.get('client_email', 'N/A')}")
            print(f"   Private Key ID: {data.get('private_key_id', 'N/A')[:20]}...")
            return True
            
        except json.JSONDecodeError:
            print("❌ Service account file is not valid JSON")
            return False
    else:
        print(f"❌ Service account file not found: {service_account_path}")
        print("💡 Please put the JSON file in the same directory as this script")
        return False

if __name__ == "__main__":
    print("🧪 Firebase Admin SDK Test")
    print("=" * 50)
    
    if check_service_account():
        test_with_admin_sdk()
    
    print("\n" + "=" * 50)
    print("✅ Test completed!") 