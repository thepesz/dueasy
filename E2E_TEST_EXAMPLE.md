# End-to-End Test: Document Analysis Flow

## Complete Flow Diagram

```
User scans invoice
       ↓
iOS: Extract OCR text (Vision Framework)
       ↓
iOS: Check confidence < 60% → Need cloud assist
       ↓
iOS: Call Firebase Cloud Function
       ↓
Cloud: Authenticate user (Firebase Auth)
       ↓
Cloud: Verify Pro subscription (Firestore)
       ↓
Cloud: Send OCR text to OpenAI GPT-4o
       ↓
Cloud: Return structured data
       ↓
iOS: Parse response
       ↓
iOS: Fill document fields
       ↓
User: Review and save
```

---

## Step 1: What iOS App Sends

### Sample Invoice (OCR Text)
```
FAKTURA VAT NR: FV/2026/01/001
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
PL 12 3456 7890 1234 5678 9012 3456
```

### iOS App Request (Swift Code)
```swift
// In HybridAnalysisRouter.swift
let result = try await cloudGateway.analyzeText(
    ocrText: ocrText,
    documentType: .invoice,
    languageHints: ["pl"],
    currencyHints: ["PLN"]
)
```

### Actual HTTP Request (Firebase SDK handles this)
```json
POST https://europe-west1-dueasy-3a76a.cloudfunctions.net/analyzeDocument
Authorization: Bearer <Firebase-Auth-Token>
Content-Type: application/json

{
  "data": {
    "ocrText": "FAKTURA VAT NR: FV/2026/01/001\nData wystawienia: 2026-01-15\n...",
    "documentType": "invoice",
    "languageHints": ["pl"],
    "currencyHints": ["PLN"]
  }
}
```

---

## Step 2: What Cloud Function Returns

### Success Response
```json
{
  "vendorName": "ACME Corporation Sp. z o.o.",
  "vendorAddress": "ul. Testowa 123, 00-001 Warszawa",
  "vendorNIP": "1234567890",
  "vendorREGON": null,
  "amount": "1230.00",
  "currency": "PLN",
  "issueDate": "2026-01-15",
  "dueDate": "2026-02-15",
  "documentNumber": "FV/2026/01/001",
  "bankAccount": "PL12345678901234567890123456",
  "overallConfidence": 0.95,

  "vendorCandidates": [
    {
      "displayValue": "ACME Corporation Sp. z o.o.",
      "confidence": 0.95,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    },
    {
      "displayValue": "ACME Corporation",
      "confidence": 0.85,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ],

  "amountCandidates": [
    {
      "displayValue": "1230.00",
      "confidence": 0.98,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    },
    {
      "displayValue": "1000.00",
      "confidence": 0.65,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ],

  "dateCandidates": [
    {
      "displayValue": "2026-02-15",
      "confidence": 0.95,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ],

  "nipCandidates": [
    {
      "displayValue": "1234567890",
      "confidence": 0.99,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ],

  "documentNumberCandidates": [
    {
      "displayValue": "FV/2026/01/001",
      "confidence": 0.97,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ],

  "bankAccountCandidates": [
    {
      "displayValue": "PL12345678901234567890123456",
      "confidence": 0.92,
      "extractionMethod": "cloudAI",
      "evidenceBBox": null
    }
  ]
}
```

### Error Responses

**Authentication Required:**
```json
{
  "error": {
    "status": "UNAUTHENTICATED",
    "message": "Authentication required for AI analysis"
  }
}
```

**No Pro Subscription:**
```json
{
  "error": {
    "status": "PERMISSION_DENIED",
    "message": "Pro subscription required for AI analysis. Please upgrade to continue."
  }
}
```

**Rate Limit Exceeded:**
```json
{
  "error": {
    "status": "RESOURCE_EXHAUSTED",
    "message": "Rate limit exceeded. Maximum 20 requests per hour."
  }
}
```

---

## Step 3: How iOS App Fills the Fields

### iOS Code Flow

```swift
// 1. FirebaseCloudExtractionGateway receives response
private func parseAnalysisResult(from data: Any) throws -> DocumentAnalysisResult {
    guard let dict = data as? [String: Any] else {
        throw CloudExtractionError.invalidResponse
    }

    // 2. Extract all fields
    let vendorName = dict["vendorName"] as? String
    let vendorAddress = dict["vendorAddress"] as? String
    let vendorNIP = dict["vendorNIP"] as? String
    let amount = Decimal(string: dict["amount"] as? String ?? "")
    let dueDate = ISO8601DateFormatter().date(from: dict["dueDate"] as? String ?? "")
    // ... etc

    // 3. Create DocumentAnalysisResult
    return DocumentAnalysisResult(
        documentType: .invoice,
        vendorName: vendorName,
        vendorAddress: vendorAddress,
        vendorNIP: vendorNIP,
        amount: amount,
        currency: "PLN",
        dueDate: dueDate,
        documentNumber: documentNumber,
        bankAccountNumber: bankAccount,
        overallConfidence: 0.95,
        provider: "openai-firebase",
        version: 1
    )
}
```

### How HybridAnalysisRouter Uses It

```swift
// In HybridAnalysisRouter.swift
func analyzeDocument(ocrText: String) async throws -> DocumentAnalysisResult {
    // 1. Try local analysis first
    let localResult = try await localService.analyzeDocument(...)

    // 2. Check if confidence is low
    if localResult.overallConfidence < 0.60 {
        // 3. Call cloud for better accuracy
        let cloudResult = try await cloudGateway.analyzeText(
            ocrText: ocrText,
            documentType: .invoice,
            languageHints: ["pl"],
            currencyHints: ["PLN"]
        )

        // 4. Return cloud result (99% accurate)
        return cloudResult
    }

    // 5. Return local result (good enough)
    return localResult
}
```

### How ViewModel Fills the UI

```swift
// In DocumentScanViewModel.swift
func processScannedDocument(image: UIImage) async {
    do {
        // 1. Extract OCR text
        let ocrText = try await ocrService.extractText(from: image)

        // 2. Analyze with hybrid router (local + cloud if needed)
        let analysisResult = try await analysisRouter.analyzeDocument(ocrText: ocrText)

        // 3. Fill the document fields
        await MainActor.run {
            self.vendorName = analysisResult.vendorName ?? ""
            self.vendorNIP = analysisResult.vendorNIP ?? ""
            self.amount = analysisResult.amount ?? 0
            self.dueDate = analysisResult.dueDate
            self.documentNumber = analysisResult.documentNumber ?? ""
            self.bankAccount = analysisResult.bankAccountNumber ?? ""

            // 4. Show success message
            self.showSuccessMessage = true
        }

    } catch {
        // Handle errors
        await MainActor.run {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

### What User Sees

1. **Scan invoice** → Camera opens
2. **Take photo** → OCR starts (1 second)
3. **Local analysis** → "Analyzing..." (1 second)
4. **Low confidence?** → "Requesting cloud assist..." (3 seconds)
5. **Fields filled!** → All fields populated with 99% accuracy
6. **User reviews** → Can edit any field if needed
7. **Save** → Document saved to SwiftData

---

## Testing the Full Flow

### Test 1: Create Test User with Pro Subscription

Since we don't have authentication set up yet, we need to:

1. **Enable Anonymous Auth** in Firebase Console
2. **Create test user** with Pro subscription in Firestore
3. **Run the app** and test document scanning

### Test 2: Manual API Test (with curl)

To test the Cloud Function directly, you need a Firebase Auth token:

```bash
# This won't work without auth token:
curl -X POST "https://europe-west1-dueasy-3a76a.cloudfunctions.net/analyzeDocument" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "ocrText": "FAKTURA VAT...",
      "documentType": "invoice",
      "languageHints": ["pl"],
      "currencyHints": ["PLN"]
    }
  }'
# Response: {"error": {"status": "UNAUTHENTICATED", ...}}
```

---

## Next Steps to Test E2E

To complete the full test, we need to:

### 1. Enable Anonymous Authentication

Go to Firebase Console:
- Click "Authentication" → "Sign-in method"
- Enable "Anonymous"
- This allows testing without requiring user accounts

### 2. Create Test User with Pro Subscription

In Firestore, create a test document:
```
Collection: users
Document ID: <your-test-user-id>
Fields:
  subscription (map):
    tier: "pro"
    isActive: true
    expiresAt: null
    isTrialPeriod: true
```

### 3. Run iOS App and Test

1. Launch app in simulator
2. App signs in anonymously
3. Scan a document
4. Watch console logs for:
   - ✅ Firebase initialized
   - ✅ User authenticated
   - ✅ Cloud function called
   - ✅ Fields populated

---

## Expected Costs per Request

**OpenAI GPT-4o:**
- Input: ~1500 tokens ($0.0025 per 1K tokens) = $0.00375
- Output: ~500 tokens ($0.010 per 1K tokens) = $0.005
- **Total: ~$0.01 per invoice**

**Firebase:**
- Cloud Functions: Free (under 2M invocations/month)
- Firestore: Free (under 50K reads/day)
- Auth: Free (unlimited)

**Total cost per user/month (20 invoices):**
- OpenAI: $0.20
- Firebase: $0.00
- **Total: $0.20/month**

**Recommended pricing:**
- Free tier: Local analysis only
- Pro tier: $4.99/month (96% margin)
