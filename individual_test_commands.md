# TRON Transaction Test Commands

## 📋 Prerequisites
You need to get these values from your app:
- **UserID**: From your current wallet
- **Full recipient address**: The complete TRON address (TLAdHP2L...dNcoko)

## 🔧 Test Commands

### Step 1: Get Sender Address
```bash
curl -X POST "https://coinceeper.com/api/Recive" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "UserID": "YOUR_USER_ID_HERE",
    "BlockchainName": "TRON"
  }'
```

### Step 2: Prepare Transaction
Replace the following values:
- `YOUR_USER_ID_HERE`: Your actual UserID
- `SENDER_ADDRESS_FROM_STEP1`: Address received from step 1
- `FULL_RECIPIENT_ADDRESS`: Complete recipient address

```bash
curl -X POST "https://coinceeper.com/api/send/prepare" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "UserID": "YOUR_USER_ID_HERE",
    "blockchain": "TRON",
    "sender_address": "SENDER_ADDRESS_FROM_STEP1",
    "recipient_address": "FULL_RECIPIENT_ADDRESS",
    "amount": "22.17902200",
    "smart_contract_address": ""
  }'
```

### Step 3: Confirm Transaction
Replace `TRANSACTION_ID_FROM_STEP2` with the transaction_id from step 2 response:

```bash
curl -X POST "https://coinceeper.com/api/send/confirm" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "tx_hash": "TRANSACTION_ID_FROM_STEP2",
    "blockchain": "TRON"
  }'
```

## 📱 How to Get Required Values

To get your UserID and full recipient address, you can:

1. **For UserID**: Check your app's secure storage or the current wallet state
2. **For recipient address**: Make sure you have the complete TRON address (not truncated)

## 🎯 Expected Flow
1. Step 1 should return your TRON wallet address
2. Step 2 should return a transaction_id if successful
3. Step 3 should confirm the transaction and return a transaction hash

## ⚠️ Important Notes
- This will create a REAL transaction on the TRON network
- Make sure you have sufficient TRX for the amount + fees
- The recipient address must be a valid TRON address
- Keep the transaction_id from step 2 for step 3
