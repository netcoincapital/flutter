#!/bin/bash

# cURL Debug Test - Compare with Flutter

echo "🔧 cURL Debug Test - TRON Transaction"
echo "===================================="

# Test Variables (same as Flutter)
USER_ID="c1bf9df0-8263-41f1-844f-2e587f9b4050"
PRIVATE_KEY="b7b9c47587f84c99d92d7f3207db9fa8a1c6689e7aa783d461c025bf216270d7"
BLOCKCHAIN="TRON"

echo "📋 Parameters:"
echo "   UserID: $USER_ID"
echo "   PrivateKey: ${PRIVATE_KEY:0:8}..."
echo "   Blockchain: $BLOCKCHAIN"
echo ""

# First prepare a transaction (for getting transaction_id)
echo "🔄 Step 1: Preparing transaction for testing..."
PREPARE_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/prepare" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"UserID\": \"test_user_tron_123\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"sender_address\": \"TWxYj1EgkXikRh3SszVUQniB6NcLNKeRfy\",
    \"recipient_address\": \"TLAdHP2Lymkbor8mjzMyzH4QnrgsdNcoko\",
    \"amount\": \"1\",
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

# Now test confirm with exact same format as Flutter
echo "🔄 Step 2: Confirming transaction (Flutter format)..."
echo "🔧 Headers:"
echo "   Content-Type: application/json"
echo "   Accept: application/json"
echo "   UserID: $USER_ID"
echo ""
echo "🔧 Request Body:"
echo "{"
echo "  \"UserID\": \"$USER_ID\","
echo "  \"transaction_id\": \"$TRANSACTION_ID\","
echo "  \"blockchain\": \"$BLOCKCHAIN\","
echo "  \"private_key\": \"$PRIVATE_KEY\""
echo "}"
echo ""

CONFIRM_RESPONSE=$(curl -s -X POST "https://coinceeper.com/api/send/confirm" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "UserID: $USER_ID" \
  -d "{
    \"UserID\": \"$USER_ID\",
    \"transaction_id\": \"$TRANSACTION_ID\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"private_key\": \"$PRIVATE_KEY\"
  }")

echo "📄 Confirm Response:"
echo "$CONFIRM_RESPONSE" | jq .
echo ""

# Check results
SUCCESS=$(echo "$CONFIRM_RESPONSE" | jq -r '.message')
STATUS_CODE=$(echo "$CONFIRM_RESPONSE" | jq -r '.status // "unknown"')

echo "🔍 Analysis:"
echo "   Message: $SUCCESS"
echo "   Status: $STATUS_CODE"
echo ""

if [ "$SUCCESS" == "Transaction sent successfully" ]; then
    echo "✅ cURL Test: SUCCESS"
    echo "   This means the Flutter app should also work!"
else
    echo "❌ cURL Test: FAILED"
    echo "   Error: $SUCCESS"
fi

echo ""
echo "📝 Note: If cURL works but Flutter doesn't, check:"
echo "   1. Request headers match"
echo "   2. Request body JSON format"
echo "   3. UserID values are identical"
echo "   4. HTTP method and URL are correct" 