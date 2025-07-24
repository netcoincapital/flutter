#!/usr/bin/env python3
"""
Test FCM Notification with Firebase Server Key
"""

import requests
import json
from datetime import datetime

# ✅ REPLACE WITH YOUR FIREBASE SERVER KEY
FIREBASE_SERVER_KEY = "AAAA_YOUR_FIREBASE_SERVER_KEY_HERE"

# Device data from database
DEVICE_TOKEN = "euYtawyFT86uVvt5L7shsS:APA91bHoic-emX8mYJNj4-l5MDz6DEA1v0IPdf0x5ri0EWlwvL6SZBnulgzCcd3pSrsOIUOCkOHAT7QNKyrMWdEhd7W-7466vzZ740lDRT9iNf0sDa7pP38"
USER_ID = "2a272775-17e9-4739-a756-67da1090dbcb"
WALLET_ID = "c2569417-736b-4352-860f-5f063948b6b1"

def test_fcm_notification():
    """Test FCM notification with real server key"""
    
    if FIREBASE_SERVER_KEY == "AAAA_YOUR_FIREBASE_SERVER_KEY_HERE":
        print("❌ Please replace FIREBASE_SERVER_KEY with your real Firebase Server Key")
        print("📝 Get it from: Firebase Console → Project Settings → Cloud Messaging → Server Key")
        return
    
    headers = {
        'Authorization': f'key={FIREBASE_SERVER_KEY}',
        'Content-Type': 'application/json',
    }
    
    # Test notification payload - مطابق Android notification format
    payload = {
        "to": DEVICE_TOKEN,
        "notification": {
            "title": "💰 Transaction Received",
            "body": "You received 0.001 BTC",
            "sound": "receive_sound",
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "icon": "notifsmall"
        },
        "data": {
            "transaction_id": f"test_tx_{int(datetime.now().timestamp())}",
            "type": "receive",
            "direction": "inbound", 
            "amount": "0.001",
            "currency": "BTC",
            "symbol": "BTC",
            "from_address": "bc1qtest123abc...",
            "to_address": "bc1qreceive456def...",
            "wallet_id": WALLET_ID,
            "user_id": USER_ID,
            "timestamp": datetime.now().isoformat()
        },
        "android": {
            "notification": {
                "channel_id": "receive_channel",
                "sound": "receive_sound",
                "priority": "high"
            }
        }
    }
    
    print("🚀 Sending FCM Notification...")
    print(f"📱 Device Token: {DEVICE_TOKEN[:30]}...")
    print(f"👤 User ID: {USER_ID}")
    print(f"🆔 Wallet ID: {WALLET_ID}")
    print(f"📧 Notification: {payload['notification']['title']}")
    
    try:
        response = requests.post(
            'https://fcm.googleapis.com/fcm/send',
            headers=headers,
            json=payload,
            timeout=30
        )
        
        print(f"\n📥 Response Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"📥 Response: {json.dumps(result, indent=2)}")
            
            if result.get('success', 0) > 0:
                print("\n✅ FCM Notification sent successfully!")
                print("📱 Check your Android device for the notification")
                print("🔊 You should hear the receive_sound.ogg")
                
                # Success details
                if 'results' in result:
                    for i, res in enumerate(result['results']):
                        if 'message_id' in res:
                            print(f"   📧 Message {i+1}: {res['message_id']}")
                        elif 'error' in res:
                            print(f"   ❌ Message {i+1} Error: {res['error']}")
            else:
                print(f"\n❌ FCM failed: {result}")
                if 'results' in result:
                    for i, res in enumerate(result['results']):
                        if 'error' in res:
                            print(f"   ❌ Error {i+1}: {res['error']}")
        else:
            print(f"❌ HTTP Error: {response.status_code}")
            print(f"❌ Response: {response.text}")
            
    except Exception as e:
        print(f"💥 Exception: {e}")

def show_instructions():
    """Show setup instructions"""
    print("📋 Setup Instructions:")
    print("=" * 50)
    print("1. Go to Firebase Console: https://console.firebase.google.com/")
    print("2. Select project: coinceeper-f2eaf")
    print("3. Go to: Settings → Project Settings → Cloud Messaging")
    print("4. Copy the 'Server Key' (starts with AAAA...)")
    print("5. Replace FIREBASE_SERVER_KEY in this script")
    print("6. Run this script again")
    print("=" * 50)

if __name__ == "__main__":
    print("🧪 FCM Notification Test with Server Key")
    print("=" * 50)
    
    if FIREBASE_SERVER_KEY == "AAAA_YOUR_FIREBASE_SERVER_KEY_HERE":
        show_instructions()
    else:
        test_fcm_notification()
        
    print("\n" + "=" * 50)
    print("✅ Test completed!") 