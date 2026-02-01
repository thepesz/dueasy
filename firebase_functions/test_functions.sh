#!/bin/bash

# Test script for DuEasy Cloud Functions
# Tests all endpoints with sample data

set -e

echo "🧪 Testing DuEasy Cloud Functions"
echo "=================================="
echo ""

# Configuration
REGION="europe-west1"
PROJECT_ID="${FIREBASE_PROJECT_ID:-your-project-id}"
BASE_URL="https://$REGION-$PROJECT_ID.cloudfunctions.net"

# Check if running against emulator
if [ "$USE_EMULATOR" = "true" ]; then
    BASE_URL="http://localhost:5001/$PROJECT_ID/$REGION"
    echo "🔧 Using emulator: $BASE_URL"
else
    echo "☁️  Using production: $BASE_URL"
fi

# Get auth token (you'll need to implement this)
# For testing, you can use Firebase Auth REST API or SDK
AUTH_TOKEN="${FIREBASE_AUTH_TOKEN}"

if [ -z "$AUTH_TOKEN" ]; then
    echo "⚠️  No auth token provided"
    echo "Set FIREBASE_AUTH_TOKEN environment variable"
    echo "For now, continuing without auth (will fail on protected endpoints)"
    echo ""
fi

# Test 1: Analyze Document (Polish Invoice)
echo "📄 Test 1: Analyze Polish Invoice"
echo "-----------------------------------"

POLISH_OCR_TEXT="FAKTURA VAT NR: FV/2026/01/001
Data wystawienia: 2026-01-15

SPRZEDAWCA:
ACME Corporation Sp. z o.o.
ul. Testowa 123
00-001 Warszawa
NIP: 1234567890

NABYWCA:
Jan Kowalski
ul. Przykładowa 45
01-234 Kraków

Lp. | Nazwa | Cena netto | VAT | Wartość brutto
1 | Usługa konsultingowa | 800,00 PLN | 23% | 984,00 PLN
2 | Szkolenie | 200,00 PLN | 23% | 246,00 PLN

Suma netto: 1 000,00 PLN
VAT 23%: 230,00 PLN
RAZEM BRUTTO: 1 230,00 PLN

Do zapłaty: 1 230,00 PLN
Termin płatności: 2026-02-15

Rachunek bankowy:
PL 12 3456 7890 1234 5678 9012 3456"

curl -X POST "$BASE_URL/analyzeDocument" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{
    \"data\": {
      \"ocrText\": \"$POLISH_OCR_TEXT\",
      \"documentType\": \"invoice\",
      \"languageHints\": [\"pl\"],
      \"currencyHints\": [\"PLN\"]
    }
  }" | jq '.'

echo ""
echo ""

# Test 2: Analyze Document (English Invoice)
echo "📄 Test 2: Analyze English Invoice"
echo "-----------------------------------"

ENGLISH_OCR_TEXT="INVOICE #INV-2026-0042
Date: January 15, 2026

FROM:
Tech Solutions Ltd.
123 Business Street
London, EC1A 1BB
VAT: GB123456789

TO:
John Smith
456 Client Avenue
Manchester, M1 1AA

Description                     Amount
Consulting Services            £800.00
Technical Support              £200.00

Subtotal:                    £1,000.00
VAT (20%):                     £200.00
Total:                       £1,200.00

Amount Due:                  £1,200.00
Due Date: February 15, 2026

Bank Details:
IBAN: GB29 NWBK 6016 1331 9268 19"

curl -X POST "$BASE_URL/analyzeDocument" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{
    \"data\": {
      \"ocrText\": \"$ENGLISH_OCR_TEXT\",
      \"documentType\": \"invoice\",
      \"languageHints\": [\"en\"],
      \"currencyHints\": [\"GBP\", \"EUR\"]
    }
  }" | jq '.'

echo ""
echo ""

# Test 3: Get Subscription Status
echo "👤 Test 3: Get Subscription Status"
echo "-----------------------------------"

curl -X POST "$BASE_URL/getSubscriptionStatus" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d '{"data": {}}' | jq '.'

echo ""
echo ""

# Test 4: Edge Case - Empty Text
echo "⚠️  Test 4: Edge Case - Empty Text"
echo "-----------------------------------"

curl -X POST "$BASE_URL/analyzeDocument" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d '{
    "data": {
      "ocrText": "",
      "documentType": "invoice",
      "languageHints": ["pl"],
      "currencyHints": ["PLN"]
    }
  }' | jq '.'

echo ""
echo ""

# Test 5: Edge Case - Very Long Text
echo "⚠️  Test 5: Edge Case - Very Long Text (should fail)"
echo "------------------------------------------------------"

LONG_TEXT=$(printf 'A%.0s' {1..150000})  # 150k characters

curl -X POST "$BASE_URL/analyzeDocument" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{
    \"data\": {
      \"ocrText\": \"$LONG_TEXT\",
      \"documentType\": \"invoice\"
    }
  }" | jq '.'

echo ""
echo ""

# Summary
echo "✅ Test suite completed"
echo ""
echo "Expected results:"
echo "  Test 1: Should extract Polish invoice fields correctly"
echo "  Test 2: Should extract English invoice fields correctly"
echo "  Test 3: Should return subscription status"
echo "  Test 4: Should return error for empty text"
echo "  Test 5: Should return error for text too long"
echo ""
echo "To run against emulator:"
echo "  USE_EMULATOR=true ./test_functions.sh"
echo ""
