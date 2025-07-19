#!/bin/bash

# Test script to simulate Flutter app request format
# This will help us debug why the Flutter app fails but cURL works

echo "🧪 Testing Flutter App Request Format"
echo "====================================="

# Use the same parameters as your successful cURL test
USER_ID="test_user_tron_123"
RECIPIENT_ADDRESS="TLAdHP2Lymkbor8mjzMyzH4QnrgsdNcoko"
SENDER_ADDRESS="TWxYj1EgkXikRh3SszVUQniB6NcLNKeRfy"
PRIVATE_KEY="b7b9c47587f84c99d92d7f3207db9fa8a1c6689e7aa783d461c025bf216270d7"

echo "📋 Test Parameters:"
echo "   UserID: $USER_ID"
echo "   Sender: $SENDER_ADDRESS"
echo "   Recipient: $RECIPIENT_ADDRESS"
echo "   Private Key: ${PRIVATE_KEY:0:8}..."
echo ""

# Step 1: Prepare Transaction (Flutter format)
echo "🔄 Step 1: Prepare Transaction (Flutter format)"
PREPARE_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/prepare" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Flutter-App/1.0" \
  -H "UserID: $USER_ID" \
  -d '{
    "UserID": "'$USER_ID'",
    "blockchain": "TRON",
    "sender_address": "'$SENDER_ADDRESS'",
    "recipient_address": "'$RECIPIENT_ADDRESS'",
    "amount": "1",
    "smart_contract_address": ""
  }')

echo "📄 Prepare Response:"
echo "$PREPARE_RESPONSE" | jq .
echo ""

# Extract transaction ID
TX_ID=$(echo "$PREPARE_RESPONSE" | jq -r '.transaction_id')
echo "🔑 Transaction ID: $TX_ID"
echo ""

# Step 2: Confirm Transaction (Flutter format)
echo "🔄 Step 2: Confirm Transaction (Flutter format)"
CONFIRM_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/confirm" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Flutter-App/1.0" \
  -H "UserID: $USER_ID" \
  -d '{
    "UserID": "'$USER_ID'",
    "transaction_id": "'$TX_ID'",
    "blockchain": "TRON",
    "private_key": "'$PRIVATE_KEY'"
  }')

echo "📄 Confirm Response:"
echo "$CONFIRM_RESPONSE" | jq .
echo ""

# Check results
SUCCESS=$(echo "$CONFIRM_RESPONSE" | jq -r '.message')
TX_HASH=$(echo "$CONFIRM_RESPONSE" | jq -r '.tx_hash // .transaction_hash')

if [ "$SUCCESS" == "Transaction sent successfully" ]; then
    echo "✅ Flutter format test: SUCCESS"
    echo "   Transaction Hash: $TX_HASH"
    echo "   Explorer: https://tronscan.org/#/transaction/$TX_HASH"
else
    echo "❌ Flutter format test: FAILED"
    echo "   Error: $SUCCESS"
fi

echo ""
echo "🔍 Comparison with your successful test:"
echo "   Your test used different UserIDs for prepare/confirm"
echo "   This test uses same UserID for both (like Flutter app)"
echo "   If this fails, we know the issue is UserID consistency" 