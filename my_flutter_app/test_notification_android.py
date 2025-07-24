#!/usr/bin/env python3
"""
Test FCM Notifications for Android Flutter App
تست نوتیفیکیشن‌های FCM برای اپ Flutter Android

Usage:
python test_notification_android.py [FCM_TOKEN]
"""

import sys
import json
import subprocess
from datetime import datetime

def send_test_notification_curl(fcm_token, server_key=None):
    """
    Send test notification using curl (without Firebase Admin SDK)
    """
    
    if not server_key:
        print("⚠️ No Firebase Server Key provided")
        print("📍 To get Server Key:")
        print("1. Go to Firebase Console")
        print("2. Project Settings → Cloud Messaging")
        print("3. Copy 'Server key'")
        print()
        return False
    
    # Prepare notification payload
    payload = {
        "to": fcm_token,
        "notification": {
            "title": "🎉 Test Notification",
            "body": "Your Laxce Wallet notifications are working!"
        },
        "data": {
            "type": "test",
            "timestamp": datetime.now().isoformat(),
            "action": "none"
        },
        "android": {
            "notification": {
                "icon": "ic_launcher_foreground",
                "color": "#16B369",
                "sound": "default",
                "channel_id": "high_importance_channel"
            }
        }
    }
    
    # Prepare curl command
    curl_cmd = [
        "curl",
        "-X", "POST",
        "-H", "Authorization: key=" + server_key,
        "-H", "Content-Type: application/json",
        "-d", json.dumps(payload),
        "https://fcm.googleapis.com/fcm/send"
    ]
    
    print("📤 Sending test notification...")
    print(f"🪙 Target FCM Token: {fcm_token[:30]}...")
    print()
    
    try:
        result = subprocess.run(curl_cmd, capture_output=True, text=True, check=True)
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            
            if response.get('success') == 1:
                print("✅ Notification sent successfully!")
                print(f"📱 Message ID: {response.get('results', [{}])[0].get('message_id', 'Unknown')}")
                return True
            else:
                print("❌ Notification failed:")
                print(f"   Error: {response.get('results', [{}])[0].get('error', 'Unknown error')}")
                return False
        else:
            print(f"❌ Curl command failed with code: {result.returncode}")
            print(f"   Error: {result.stderr}")
            return False
            
    except subprocess.CalledProcessError as e:
        print(f"❌ Curl command error: {e}")
        return False
    except json.JSONDecodeError as e:
        print(f"❌ JSON parsing error: {e}")
        print(f"   Response: {result.stdout}")
        return False

def send_transaction_notification_curl(fcm_token, server_key):
    """
    Send transaction notification test
    """
    
    payload = {
        "to": fcm_token,
        "notification": {
            "title": "Transaction Confirmed ✅",
            "body": "Your 0.5 ETH transfer has been confirmed!"
        },
        "data": {
            "type": "transaction",
            "transactionId": "tx_test_123456",
            "hash": "0x1234567890abcdef...",
            "amount": "0.5",
            "symbol": "ETH",
            "status": "confirmed",
            "explorerUrl": "https://etherscan.io/tx/0x1234567890abcdef...",
            "action": "view_transaction",
            "timestamp": datetime.now().isoformat()
        },
        "android": {
            "notification": {
                "icon": "ic_launcher_foreground",
                "color": "#16B369",
                "sound": "default",
                "channel_id": "high_importance_channel"
            }
        }
    }
    
    curl_cmd = [
        "curl",
        "-X", "POST",
        "-H", "Authorization: key=" + server_key,
        "-H", "Content-Type: application/json",
        "-d", json.dumps(payload),
        "https://fcm.googleapis.com/fcm/send"
    ]
    
    print("📤 Sending transaction notification...")
    
    try:
        result = subprocess.run(curl_cmd, capture_output=True, text=True, check=True)
        response = json.loads(result.stdout)
        
        if response.get('success') == 1:
            print("✅ Transaction notification sent!")
            return True
        else:
            print("❌ Transaction notification failed:")
            print(f"   Error: {response.get('results', [{}])[0].get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print(f"❌ Error sending transaction notification: {e}")
        return False

def get_fcm_token_instructions():
    """
    Show instructions for getting FCM token
    """
    print("📱 How to get your FCM Token:")
    print("=" * 50)
    print("1. Open Laxce Wallet app")
    print("2. Go to Settings → Notifications")
    print("3. Tap 'Enable Notifications'")
    print("4. Accept notification permissions")
    print("5. Tap 'Check Status'")
    print("6. Copy the FCM token")
    print()
    print("Or check Android logs:")
    print("adb logcat | grep 'FCM Token'")
    print()

def main():
    print("🔥 Laxce Wallet - Android FCM Notification Tester")
    print("=" * 60)
    
    if len(sys.argv) < 2:
        print("❌ Usage: python test_notification_android.py [FCM_TOKEN] [SERVER_KEY]")
        print()
        get_fcm_token_instructions()
        print("🔑 Firebase Server Key:")
        print("   Get from: Firebase Console → Project Settings → Cloud Messaging")
        print()
        print("Example:")
        print("python test_notification_android.py fGcK7-8x... AAAA1234...")
        sys.exit(1)
    
    fcm_token = sys.argv[1]
    server_key = sys.argv[2] if len(sys.argv) > 2 else None
    
    if len(fcm_token) < 50:
        print("⚠️ Warning: FCM token seems too short")
        print("   Make sure you copied the complete token")
        print()
    
    print(f"🪙 FCM Token: {fcm_token[:30]}...")
    if server_key:
        print(f"🔑 Server Key: {server_key[:10]}...")
    print()
    
    if not server_key:
        print("⚠️ No server key provided - showing instructions only")
        print()
        print("🔗 Manual Test Instructions:")
        print("=" * 40)
        print("1. Go to: https://console.firebase.google.com/")
        print("2. Select your Laxce Wallet project")
        print("3. Cloud Messaging → 'Send your first message'")
        print("4. Title: Transaction Confirmed")
        print("5. Body: Your 0.5 ETH transfer was successful!")
        print("6. Target: 'Single device'")
        print(f"7. FCM token: {fcm_token}")
        print("8. Additional options → Custom data:")
        print("   type: transaction")
        print("   amount: 0.5")
        print("   symbol: ETH")
        print("   status: confirmed")
        print("9. Click 'Send'")
        return
    
    # Test options
    print("📋 Available tests:")
    print("1. Basic test notification")
    print("2. Transaction notification")
    print("3. Show manual test instructions")
    print()
    
    choice = input("Select test type (1-3): ").strip()
    
    if choice == "1":
        success = send_test_notification_curl(fcm_token, server_key)
        if success:
            print()
            print("🎉 Test completed! Check your Android device for notification.")
        
    elif choice == "2":
        success = send_transaction_notification_curl(fcm_token, server_key)
        if success:
            print()
            print("💰 Transaction notification sent! Check your device.")
            
    elif choice == "3":
        print()
        print("🔗 Firebase Console Manual Test:")
        print("=" * 40)
        print("Go to Firebase Console and send test message manually")
        print(f"Target FCM Token: {fcm_token}")
        
    else:
        print("❌ Invalid choice")

    # Show debugging info
    print()
    print("🔧 Debugging Info:")
    print("=" * 30)
    print("• Check Android logs: adb logcat | grep -E '(FCM|Firebase|MyFirebaseMessaging)'")
    print("• Verify app permissions: Settings → Apps → Laxce → Notifications")
    print("• Check notification channels in Android settings")
    print("• Ensure app is in foreground or background (not killed)")

if __name__ == "__main__":
    main() 