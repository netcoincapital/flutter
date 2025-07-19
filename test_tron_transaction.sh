#!/bin/bash

# TRON Transaction Test Script
# Base URL
BASE_URL="https://coinceeper.com/api"

# Test data (you need to replace these with your actual values)
USER_ID="test_user_123"  # Replace with your actual UserID
RECIPIENT_ADDRESS="TLAdHP2L6dhCpBWbRFnCiWPvqmHbsZ3dNcoko"  # Replace with full recipient address
AMOUNT="22.17902200"
BLOCKCHAIN="TRON"

echo "🚀 Starting TRON Transaction Test"
echo "=================================="

# Step 1: Get sender address
echo "📍 Step 1: Getting sender address..."
SENDER_RESPONSE=$(curl -s -X POST "$BASE_URL/Recive" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"UserID\": \"$USER_ID\",
    \"BlockchainName\": \"$BLOCKCHAIN\"
  }")

echo "Response: $SENDER_RESPONSE"

# Extract sender address from response (you may need to adjust this based on actual response)
SENDER_ADDRESS=$(echo "$SENDER_RESPONSE" | jq -r '.PublicAddress // empty')

if [ -z "$SENDER_ADDRESS" ] || [ "$SENDER_ADDRESS" = "null" ]; then
  echo "❌ Failed to get sender address"
  exit 1
fi

echo "✅ Sender address: $SENDER_ADDRESS"
echo ""

# Step 2: Prepare transaction
echo "📝 Step 2: Preparing transaction..."
PREPARE_RESPONSE=$(curl -s -X POST "$BASE_URL/send/prepare" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"UserID\": \"$USER_ID\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"sender_address\": \"$SENDER_ADDRESS\",
    \"recipient_address\": \"$RECIPIENT_ADDRESS\",
    \"amount\": \"$AMOUNT\",
    \"smart_contract_address\": \"\"
  }")

echo "Response: $PREPARE_RESPONSE"

# Extract transaction ID from response
TX_ID=$(echo "$PREPARE_RESPONSE" | jq -r '.transaction_id // empty')

if [ -z "$TX_ID" ] || [ "$TX_ID" = "null" ]; then
  echo "❌ Failed to prepare transaction"
  exit 1
fi

echo "✅ Transaction prepared successfully!"
echo "Transaction ID: $TX_ID"
echo ""

# Step 3: Confirm transaction
echo "✅ Step 3: Confirming transaction..."
CONFIRM_RESPONSE=$(curl -s -X POST "$BASE_URL/send/confirm" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"tx_hash\": \"$TX_ID\",
    \"blockchain\": \"$BLOCKCHAIN\"
  }")

echo "Response: $CONFIRM_RESPONSE"

# Check if transaction was confirmed
SUCCESS=$(echo "$CONFIRM_RESPONSE" | jq -r '.success // false')

if [ "$SUCCESS" = "true" ]; then
  echo "🎉 Transaction confirmed successfully!"
  TX_HASH=$(echo "$CONFIRM_RESPONSE" | jq -r '.transaction_hash // empty')
  echo "Transaction Hash: $TX_HASH"
else
  echo "❌ Transaction confirmation failed"
  ERROR_MSG=$(echo "$CONFIRM_RESPONSE" | jq -r '.message // "Unknown error"')
  echo "Error: $ERROR_MSG"
fi

echo ""
echo "🏁 Transaction test completed!"
