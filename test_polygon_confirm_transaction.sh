#!/bin/bash

# Test Polygon Transaction Confirm with cURL
# This script replicates the exact same flow as the Flutter app

echo "=== Testing Polygon Transaction Confirm with cURL ==="
echo ""

# Configuration
BASE_URL="https://coinceeper.com/api/"
USER_ID="c1bf9df0-8263-41f1-844f-2e587f9b4050"
SENDER_ADDRESS="0x68Ba7F66B09783977E36AA7bD8390b812742853C"
RECIPIENT_ADDRESS="0x184ac75b74C77D5BF3b3BffB5Ed26aE091B3feD1"
AMOUNT="0.01000000"
BLOCKCHAIN="polygon"
PRIVATE_KEY="b7b9c47587f84c99d92d7f3207db9fa8a1c6689e7aa783d461c025bf216270d7"

echo "🔧 TEST CONFIGURATION:"
echo "   Base URL: $BASE_URL"
echo "   UserID: $USER_ID"
echo "   Sender: $SENDER_ADDRESS"
echo "   Recipient: $RECIPIENT_ADDRESS"
echo "   Amount: $AMOUNT"
echo "   Blockchain: $BLOCKCHAIN"
echo "   Private Key: ${PRIVATE_KEY:0:16}..."
echo ""

# Step 1: Prepare Transaction
echo "🚀 Step 1: Prepare Transaction"
echo "   URL: ${BASE_URL}send/prepare"
echo ""

PREPARE_RESPONSE=$(curl -s -w "\nSTATUS_CODE:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Flutter-App/1.0" \
  -d "{
    \"UserID\": \"$USER_ID\",
    \"blockchain\": \"$BLOCKCHAIN\",
    \"sender_address\": \"$SENDER_ADDRESS\",
    \"recipient_address\": \"$RECIPIENT_ADDRESS\",
    \"amount\": \"$AMOUNT\",
    \"smart_contract_address\": \"\"
  }" \
  "${BASE_URL}send/prepare")

# Extract status code and response body
STATUS_CODE=$(echo "$PREPARE_RESPONSE" | grep "STATUS_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$PREPARE_RESPONSE" | sed '/STATUS_CODE:/d')

echo "📥 Prepare Response:"
echo "   Status Code: $STATUS_CODE"
echo "   Response Body: $RESPONSE_BODY"
echo ""

if [ "$STATUS_CODE" != "200" ]; then
    echo "❌ Prepare transaction failed with status $STATUS_CODE"
    echo "   Response: $RESPONSE_BODY"
    exit 1
fi

# Extract transaction_id from response
TRANSACTION_ID=$(echo "$RESPONSE_BODY" | grep -o '"transaction_id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TRANSACTION_ID" ]; then
    echo "❌ Could not extract transaction_id from prepare response"
    echo "   Response: $RESPONSE_BODY"
    exit 1
fi

echo "✅ Prepare successful!"
echo "   Transaction ID: $TRANSACTION_ID"
echo ""

# Step 2: Confirm Transaction
echo "🚀 Step 2: Confirm Transaction"
echo "   URL: ${BASE_URL}send/confirm"
echo ""

echo "📤 Confirm Request Data:"
echo "   UserID: \"$USER_ID\""
echo "   transaction_id: \"$TRANSACTION_ID\""
echo "   blockchain: \"$BLOCKCHAIN\""
echo "   private_key: \"${PRIVATE_KEY:0:16}...\""
echo ""

CONFIRM_REQUEST_JSON="{
  \"UserID\": \"$USER_ID\",
  \"transaction_id\": \"$TRANSACTION_ID\",
  \"blockchain\": \"$BLOCKCHAIN\",
  \"private_key\": \"$PRIVATE_KEY\"
}"

echo "📋 Full Request JSON:"
echo "$CONFIRM_REQUEST_JSON"
echo ""

CONFIRM_RESPONSE=$(curl -s -w "\nSTATUS_CODE:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Flutter-App/1.0" \
  -H "UserID: $USER_ID" \
  -d "$CONFIRM_REQUEST_JSON" \
  "${BASE_URL}send/confirm")

# Extract status code and response body
CONFIRM_STATUS_CODE=$(echo "$CONFIRM_RESPONSE" | grep "STATUS_CODE:" | cut -d: -f2)
CONFIRM_RESPONSE_BODY=$(echo "$CONFIRM_RESPONSE" | sed '/STATUS_CODE:/d')

echo "📥 Confirm Response:"
echo "   Status Code: $CONFIRM_STATUS_CODE"
echo "   Response Body: $CONFIRM_RESPONSE_BODY"
echo ""

# Analyze the response
if [ "$CONFIRM_STATUS_CODE" = "200" ]; then
    echo "✅ Confirm transaction successful!"
    
    # Try to extract transaction hash
    TX_HASH=$(echo "$CONFIRM_RESPONSE_BODY" | grep -o '"tx_hash":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$TX_HASH" ]; then
        echo "   Transaction Hash: $TX_HASH"
    fi
    
elif [ "$CONFIRM_STATUS_CODE" = "400" ]; then
    echo "❌ Confirm transaction failed with 400 Bad Request"
    echo ""
    echo "🔍 DEBUGGING 400 ERROR:"
    echo "   This might be a success response disguised as an error"
    echo "   Checking response for success indicators..."
    echo ""
    
    # Check for success indicators in 400 response
    if echo "$CONFIRM_RESPONSE_BODY" | grep -q "Transaction sent successfully"; then
        echo "✅ Found 'Transaction sent successfully' in 400 response!"
        TX_HASH=$(echo "$CONFIRM_RESPONSE_BODY" | grep -o '"tx_hash":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$TX_HASH" ]; then
            echo "   Transaction Hash: $TX_HASH"
            echo "   🎯 This is actually a successful transaction!"
        fi
    elif echo "$CONFIRM_RESPONSE_BODY" | grep -q '"status":"sent"'; then
        echo "✅ Found status 'sent' in 400 response!"
        echo "   🎯 This is actually a successful transaction!"
    else
        echo "❌ No success indicators found in 400 response"
        echo "   This is a genuine error"
    fi
    
else
    echo "❌ Confirm transaction failed with status $CONFIRM_STATUS_CODE"
    echo "   Response: $CONFIRM_RESPONSE_BODY"
fi

echo ""
echo "=== cURL Test Complete ==="
echo ""
echo "🔧 COMPARISON WITH FLUTTER:"
echo "   1. Check if Flutter sends the same request format"
echo "   2. Verify UserID matches exactly"
echo "   3. Verify blockchain name is lowercase"
echo "   4. Verify all JSON field names match"
echo "   5. Check if Flutter handles 400 responses with success data" 