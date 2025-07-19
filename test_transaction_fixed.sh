#!/bin/bash

# TRON Transaction Test Script - Fixed Version

echo "🚀 Testing TRON Transaction Flow (Fixed)"
echo "=========================================="

# Variables
USER_ID="test_user_tron_123"
REAL_USER_ID="c1bf9df0-8263-41f1-844f-2e587f9b4050"
PRIVATE_KEY="b7b9c47587f84c99d92d7f3207db9fa8a1c6689e7aa783d461c025bf216270d7"
SENDER_ADDRESS="TWxYj1EgkXikRh3SszVUQniB6NcLNKeRfy"
RECEIVER_ADDRESS="TLAdHP2Lymkbor8mjzMyzH4QnrgsdNcoko"
AMOUNT="1"
BLOCKCHAIN="TRON"

echo "📋 Test Parameters:"
echo "   User ID: $USER_ID"
echo "   Real User ID: $REAL_USER_ID"
echo "   Sender: $SENDER_ADDRESS"
echo "   Receiver: $RECEIVER_ADDRESS"
echo "   Amount: $AMOUNT TRX"
echo "   Blockchain: $BLOCKCHAIN"
echo ""

# Step 1: Prepare Transaction
echo "🔄 Step 1: Preparing transaction..."
PREPARE_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/prepare" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"UserID\": \"$USER_ID\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"sender_address\": \"$SENDER_ADDRESS\",
    \"recipient_address\": \"$RECEIVER_ADDRESS\",
    \"amount\": \"$AMOUNT\",
    \"smart_contract_address\": \"\"
  }")

echo "📄 Prepare Response:"
echo "$PREPARE_RESPONSE" | jq .
echo ""

# Extract transaction_id
TRANSACTION_ID=$(echo "$PREPARE_RESPONSE" | jq -r '.transaction_id')

if [ "$TRANSACTION_ID" == "null" ] || [ -z "$TRANSACTION_ID" ]; then
    echo "❌ Failed to get transaction_id from prepare response"
    exit 1
fi

echo "✅ Transaction ID: $TRANSACTION_ID"
echo ""

# Step 2: Confirm Transaction (Fixed Version)
echo "🔄 Step 2: Confirming transaction (Fixed)..."
CONFIRM_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/confirm" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "UserID: $REAL_USER_ID" \
  -d "{
    \"UserID\": \"$REAL_USER_ID\",
    \"transaction_id\": \"$TRANSACTION_ID\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"private_key\": \"$PRIVATE_KEY\"
  }")

echo "📄 Confirm Response:"
echo "$CONFIRM_RESPONSE" | jq .
echo ""

# Check results
SUCCESS=$(echo "$CONFIRM_RESPONSE" | jq -r '.message')
TX_HASH=$(echo "$CONFIRM_RESPONSE" | jq -r '.tx_hash // .transaction_hash')

if [ "$SUCCESS" == "Transaction sent successfully" ]; then
    echo "✅ Transaction confirmed successfully!"
    echo "   Transaction Hash: $TX_HASH"
    echo "   Explorer: https://tronscan.org/#/transaction/$TX_HASH"
    
    # Test the complete flow
    echo ""
    echo "🎉 COMPLETE FLOW TEST RESULTS:"
    echo "=================================="
    echo "✅ PREPARE: SUCCESS"
    echo "✅ CONFIRM: SUCCESS"
    echo "✅ TRANSACTION: SENT"
    echo "✅ HASH: $TX_HASH"
    echo ""
    echo "🔧 FLUTTER APP SHOULD NOW WORK WITH THESE PARAMETERS:"
    echo "   - UserID: $REAL_USER_ID"
    echo "   - Private Key: $PRIVATE_KEY (first 8 chars)"
    echo "   - Blockchain: $BLOCKCHAIN"
    echo "   - API Format: {UserID, transaction_id, blockchain, private_key}"
    echo ""
else
    echo "❌ Transaction failed"
    echo "   Message: $SUCCESS"
    echo "   Response: $CONFIRM_RESPONSE"
fi 