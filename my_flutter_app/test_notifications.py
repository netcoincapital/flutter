#!/usr/bin/env python3
"""
🔔 Laxce Wallet Notification Test Script
تست کننده سیستم نوتیفیکیشن برای اپلیکیشن Laxce Wallet

Usage: python test_notifications.py [FCM_TOKEN]
"""

import requests
import json
import sys
import time
from typing import Dict, Any, Optional

# Firebase Server Key for coinceeper-f2eaf project
SERVER_KEY = "AIzaSyBnmgQ6SVmxoAXUq4x5HvfA0bppDD_HO3Y"
FCM_URL = "https://fcm.googleapis.com/fcm/send"

class NotificationTester:
    def __init__(self, server_key: str):
        self.server_key = server_key
        self.headers = {
            "Authorization": f"key={server_key}",
            "Content-Type": "application/json"
        }
        
    def send_notification(self, token: str, payload: Dict[str, Any]) -> bool:
        """Send a notification to FCM"""
        try:
            response = requests.post(FCM_URL, json=payload, headers=self.headers)
            
            if response.status_code == 200:
                result = response.json()
                if result.get('success', 0) > 0:
                    print(f"✅ Notification sent successfully")
                    print(f"   Message ID: {result.get('results', [{}])[0].get('message_id', 'N/A')}")
                    return True
                else:
                    print(f"❌ Failed to send notification")
                    print(f"   Error: {result.get('results', [{}])[0].get('error', 'Unknown error')}")
                    return False
            else:
                print(f"❌ HTTP Error: {response.status_code}")
                print(f"   Response: {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Exception occurred: {e}")
            return False

    def test_receive_notification(self, token: str) -> bool:
        """Test receive crypto notification"""
        print("\n📥 Testing RECEIVE notification...")
        
        payload = {
            "to": token,
            "notification": {
                "title": "💰 Received: 0.001 BTC",
                "body": "From 1A1zP1eP2RdK7WbKAXYqPBZ8CQUXBaXr4k"
            },
            "data": {
                "type": "receive",
                "transaction_id": "test_receive_123",
                "amount": "0.001",
                "currency": "BTC",
                "from_address": "1A1zP1eP2RdK7WbKAXYqPBZ8CQUXBaXr4k",
                "to_address": "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                "wallet_id": "test-wallet-001"
            }
        }
        
        return self.send_notification(token, payload)
    
    def test_send_notification(self, token: str) -> bool:
        """Test send crypto notification"""
        print("\n📤 Testing SEND notification...")
        
        payload = {
            "to": token,
            "notification": {
                "title": "💸 Sent: 0.005 ETH",
                "body": "To 0x742d35Cc6e3F78e8ced28E9A..."
            },
            "data": {
                "type": "send",
                "transaction_id": "test_send_456",
                "amount": "0.005",
                "currency": "ETH",
                "from_address": "0x8ba1f109551bD432803012645Hac136c22AdbF6",
                "to_address": "0x742d35Cc6e3F78e8ced28E9A42f7C7e3fD901A5",
                "wallet_id": "test-wallet-001"
            }
        }
        
        return self.send_notification(token, payload)
    
    def test_welcome_notification(self, token: str) -> bool:
        """Test welcome notification"""
        print("\n👋 Testing WELCOME notification...")
        
        payload = {
            "to": token,
            "notification": {
                "title": "🎉 Welcome to Laxce Wallet!",
                "body": "Your crypto wallet is ready to use"
            },
            "data": {
                "type": "welcome",
                "wallet_id": "test-wallet-001",
                "user_id": "test-user-001"
            }
        }
        
        return self.send_notification(token, payload)
    
    def test_price_alert_notification(self, token: str) -> bool:
        """Test price alert notification"""
        print("\n📈 Testing PRICE ALERT notification...")
        
        payload = {
            "to": token,
            "notification": {
                "title": "🚨 Price Alert: Bitcoin",
                "body": "BTC has reached $45,000! (+5.2%)"
            },
            "data": {
                "type": "price_alert",
                "symbol": "BTC",
                "current_price": "45000",
                "change_percent": "5.2",
                "target_price": "45000"
            }
        }
        
        return self.send_notification(token, payload)
    
    def test_legacy_transaction_notification(self, token: str) -> bool:
        """Test legacy transaction notification (for backward compatibility)"""
        print("\n📊 Testing LEGACY TRANSACTION notification...")
        
        payload = {
            "to": token,
            "notification": {
                "title": "💳 Transaction Confirmed",
                "body": "Your transaction has been confirmed"
            },
            "data": {
                "type": "transaction",
                "direction": "inbound",  # inbound = receive, outbound = send
                "transaction_id": "test_legacy_789",
                "amount": "0.002",
                "symbol": "BTC",
                "status": "confirmed"
            }
        }
        
        return self.send_notification(token, payload)

    def run_all_tests(self, token: str) -> Dict[str, bool]:
        """Run all notification tests"""
        print(f"🔔 Starting notification tests for token: {token[:20]}...")
        
        tests = {
            "receive": self.test_receive_notification,
            "send": self.test_send_notification,
            "welcome": self.test_welcome_notification,
            "price_alert": self.test_price_alert_notification,
            "legacy": self.test_legacy_transaction_notification
        }
        
        results = {}
        
        for test_name, test_func in tests.items():
            try:
                results[test_name] = test_func(token)
                time.sleep(2)  # Wait between tests
            except Exception as e:
                print(f"❌ Error in {test_name} test: {e}")
                results[test_name] = False
        
        return results

def print_results(results: Dict[str, bool]):
    """Print test results summary"""
    print("\n" + "="*50)
    print("📊 TEST RESULTS SUMMARY")
    print("="*50)
    
    passed = sum(1 for success in results.values() if success)
    total = len(results)
    
    for test_name, success in results.items():
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"   {test_name.ljust(15)} : {status}")
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Notification system is working correctly.")
    else:
        print("⚠️  Some tests failed. Check the error messages above.")

def main():
    """Main function"""
    print("🔔 Laxce Wallet Notification Tester")
    print("===================================\n")
    
    # Get FCM token from command line or prompt user
    if len(sys.argv) > 1:
        fcm_token = sys.argv[1]
    else:
        print("Please provide your FCM token:")
        print("1. Run the Flutter app")
        print("2. Check the console for: '🪙 FCM Token: [YOUR_TOKEN]'")
        print("3. Copy the token and paste it here")
        fcm_token = input("\nFCM Token: ").strip()
    
    if not fcm_token:
        print("❌ No FCM token provided. Exiting.")
        sys.exit(1)
    
    # Validate token format (basic check)
    if len(fcm_token) < 100:
        print("⚠️  Warning: FCM token seems too short. Make sure you copied the complete token.")
        confirm = input("Continue anyway? (y/N): ").strip().lower()
        if confirm != 'y':
            sys.exit(1)
    
    # Run tests
    tester = NotificationTester(SERVER_KEY)
    results = tester.run_all_tests(fcm_token)
    
    # Print results
    print_results(results)

if __name__ == "__main__":
    main() 