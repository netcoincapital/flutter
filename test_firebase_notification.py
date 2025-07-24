#!/usr/bin/env python3
"""
Test Firebase FCM Notification directly
"""

import requests
import json
from datetime import datetime

# Firebase Server Key - باید از Firebase Console دریافت شود
# برای تست، از public FCM testing endpoint استفاده می‌کنیم
FCM_SERVER_KEY = "YOUR_FIREBASE_SERVER_KEY_HERE"
FCM_URL = "https://fcm.googleapis.com/fcm/send"

# Device Token from database
DEVICE_TOKEN = "euYtawyFT86uVvt5L7shsS:APA91bHoic-emX8mYJNj4-l5MDz6DEA1v0IPdf0x5ri0EWlwvL6SZBnulgzCcd3pSrsOIUOCkOHAT7QNKyrMWdEhd7W-7466vzZ740lDRT9iNf0sDa7pP38"

def test_fcm_notification():
    """Test Firebase FCM notification directly"""
    
    headers = {
        'Authorization': f'key={FCM_SERVER_KEY}',
        'Content-Type': 'application/json',
    }
    
    # Test notification payload
    payload = {
        "to": DEVICE_TOKEN,
        "notification": {
            "title": "💰 Test Transaction",
            "body": "Received: 0.001 BTC from Flutter App Test",
            "sound": "receive_sound",
            "click_action": "FLUTTER_NOTIFICATION_CLICK"
        },
        "data": {
            "transaction_id": f"test_tx_{int(datetime.now().timestamp())}",
            "type": "receive",
            "direction": "inbound", 
            "amount": "0.001",
            "currency": "BTC",
            "symbol": "BTC",
            "from_address": "bc1qtest...",
            "to_address": "bc1qreceive...",
            "wallet_id": "c2569417-736b-4352-860f-5f063948b6b1",
            "user_id": "2a272775-17e9-4739-a756-67da1090dbcb"
        },
        "android": {
            "notification": {
                "channel_id": "receive_channel",
                "sound": "receive_sound",
                "priority": "high"
            }
        }
    }
    
    print("🚀 Sending FCM Test Notification...")
    print(f"📱 Device Token: {DEVICE_TOKEN[:30]}...")
    print(f"📤 Payload: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(FCM_URL, headers=headers, json=payload)
        
        print(f"\n📥 Response Status: {response.status_code}")
        print(f"📥 Response Headers: {dict(response.headers)}")
        print(f"📥 Response Body: {response.text}")
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success', 0) > 0:
                print("✅ FCM Notification sent successfully!")
                print("📱 Check your Android device for the notification")
            else:
                print(f"❌ FCM failed: {result}")
        else:
            print(f"❌ HTTP Error: {response.status_code}")
            
    except Exception as e:
        print(f"💥 Exception: {e}")

def test_without_server_key():
    """Test notification simulation (for debugging)"""
    print("\n🔍 Testing notification format (simulation only):")
    
    notification_data = {
        "title": "💰 Received: 0.001 BTC", 
        "body": "From bc1qtest...abc123",
        "data": {
            "transaction_id": f"tx_{int(datetime.now().timestamp())}",
            "type": "receive",
            "amount": "0.001", 
            "currency": "BTC",
            "user_id": "2a272775-17e9-4739-a756-67da1090dbcb",
            "wallet_id": "c2569417-736b-4352-860f-5f063948b6b1"
        }
    }
    
    print("📋 Notification Format:")
    print(json.dumps(notification_data, indent=2, ensure_ascii=False))
    
    # Test device token validation
    if DEVICE_TOKEN.startswith('euYtawyF'):
        print("✅ Device token format looks correct (starts with euYtawyF)")
        print(f"✅ Token length: {len(DEVICE_TOKEN)} characters")
    else:
        print("❌ Device token format may be incorrect")

if __name__ == "__main__":
    print("🧪 Firebase FCM Notification Test")
    print("=" * 50)
    
    # Test without server key first (format validation)
    test_without_server_key()
    
    print("\n" + "=" * 50)
    print("⚠️  To test actual FCM sending:")
    print("1. Get Firebase Server Key from Firebase Console")
    print("2. Replace FCM_SERVER_KEY in this script")
    print("3. Run the script again")
    print("=" * 50)
    
    # If you have server key, uncomment this:
    # test_fcm_notification() 