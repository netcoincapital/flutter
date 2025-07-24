#!/usr/bin/env python3
"""
Test Local Notification simulation
برای شبیه‌سازی notification بدون نیاز به Firebase server key
"""

import json
from datetime import datetime
import subprocess
import sys

def send_android_notification():
    """Send test notification using ADB"""
    
    device_data = {
        "user_id": "2a272775-17e9-4739-a756-67da1090dbcb",
        "wallet_id": "c2569417-736b-4352-860f-5f063948b6b1", 
        "device_token": "euYtawyFT86uVvt5L7shsS:APA91bHoic-emX8mYJNj4-l5MDz6DEA1v0IPdf0x5ri0EWlwvL6SZBnulgzCcd3pSrsOIUOCkOHAT7QNKyrMWdEhd7W-7466vzZ740lDRT9iNf0sDa7pP38"
    }
    
    notification_data = {
        "title": "💰 Transaction Received",
        "body": "You received 0.001 BTC",
        "data": {
            "transaction_id": f"tx_{int(datetime.now().timestamp())}",
            "type": "receive",
            "direction": "inbound",
            "amount": "0.001",
            "currency": "BTC", 
            "symbol": "BTC",
            "from_address": "bc1qtest123...",
            "to_address": "bc1qreceive456...",
            "wallet_id": device_data["wallet_id"],
            "user_id": device_data["user_id"]
        }
    }
    
    print("📱 Device Information:")
    print(f"   UserID: {device_data['user_id']}")
    print(f"   WalletID: {device_data['wallet_id']}")
    print(f"   Token: {device_data['device_token'][:30]}...")
    
    print("\n📧 Notification Content:")
    print(json.dumps(notification_data, indent=2, ensure_ascii=False))
    
    # Check if ADB is available
    try:
        result = subprocess.run(['adb', 'devices'], capture_output=True, text=True)
        if 'RF8N8267GJX' in result.stdout:
            print("\n📱 Android device detected!")
            
            # Send test notification via ADB
            intent_extra = json.dumps(notification_data['data']).replace('"', '\\"')
            
            adb_command = [
                'adb', '-s', 'RF8N8267GJX', 'shell', 'am', 'start',
                '-a', 'android.intent.action.MAIN',
                '-c', 'android.intent.category.LAUNCHER',
                '-n', 'com.example.my_flutter_app/.MainActivity',
                '--es', 'notification_data', intent_extra
            ]
            
            print(f"\n🚀 Sending notification via ADB...")
            result = subprocess.run(adb_command, capture_output=True, text=True)
            
            if result.returncode == 0:
                print("✅ Intent sent successfully!")
                print("📱 Check your device for the notification")
            else:
                print(f"❌ ADB command failed: {result.stderr}")
                
        else:
            print("\n⚠️  Android device not found via ADB")
            print("   Make sure USB debugging is enabled")
            
    except FileNotFoundError:
        print("\n⚠️  ADB not found. Install Android SDK Platform Tools")
    except Exception as e:
        print(f"\n❌ Error: {e}")

def simulate_notification_flow():
    """Simulate the complete notification flow"""
    
    print("\n🔄 Notification Flow Simulation:")
    print("=" * 50)
    
    steps = [
        "1. ✅ User creates/imports wallet",
        "2. ✅ Device registers with backend", 
        "3. ✅ Device token saved in database",
        "4. 🔄 Transaction occurs on blockchain",
        "5. 🔄 Backend detects transaction",
        "6. 🔄 Backend sends FCM notification",
        "7. 📱 User receives notification"
    ]
    
    for step in steps:
        print(f"   {step}")
    
    print("\n✅ Current Status:")
    print("   - Steps 1-3: COMPLETED ✅")
    print("   - Steps 4-7: NEED TESTING 🔄")
    
    print("\n🎯 What to test next:")
    print("   1. Flutter Debug Interface")
    print("   2. Manual notification trigger")
    print("   3. Real transaction simulation")

if __name__ == "__main__":
    print("🧪 Local Notification Test")
    print("=" * 50)
    
    simulate_notification_flow()
    send_android_notification()
    
    print("\n" + "=" * 50)
    print("✅ Test completed! Check your Flutter app for notifications.") 