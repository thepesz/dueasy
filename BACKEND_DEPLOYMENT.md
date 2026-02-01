## Backend Deployment Guide - Firebase Cloud Functions + OpenAI

This guide explains how to deploy the backend Cloud Functions that power DuEasy's Pro tier AI analysis features.

## Architecture Overview

```
┌─────────────┐          ┌──────────────────┐          ┌─────────────┐
│  iOS App    │  HTTPS   │ Cloud Functions  │   API    │   OpenAI    │
│  (Client)   ├─────────►│   (Firebase)     ├─────────►│  (GPT-4o)   │
└─────────────┘          └──────────────────┘          └─────────────┘
                                   │
                                   │ Auth
                                   ▼
                         ┌──────────────────┐
                         │  Firebase Auth   │
                         └──────────────────┘
```

### Data Flow

1. **Client** sends OCR text to Cloud Function (HTTPS callable)
2. **Cloud Function** validates auth token
3. **Cloud Function** calls OpenAI API with structured prompt
4. **OpenAI** returns extracted fields as JSON
5. **Cloud Function** validates and returns to client

**Privacy**: Images never leave the device. Only OCR text is sent to cloud.

## Prerequisites

- Node.js 18+ or 20+
- Firebase CLI: `npm install -g firebase-tools`
- OpenAI API key: https://platform.openai.com/api-keys
- Firebase project (created in FIREBASE_SETUP.md)

## Step 1: Initialize Firebase Functions

```bash
# Navigate to project root
cd /path/to/DuEasy

# Login to Firebase
firebase login

# Initialize Functions (if not already done)
firebase init functions
```

Select:
- ✅ Use existing project (select your DuEasy project)
- ✅ JavaScript
- ❌ ESLint (optional)
- ✅ Install dependencies with npm

This creates a `functions/` directory.

## Step 2: Install Dependencies

```bash
cd functions
npm install --save openai@^4.0.0
npm install --save firebase-functions@^4.0.0
npm install --save firebase-admin@^11.0.0
```

## Step 3: Create Cloud Functions

Create `functions/index.js`:

\`\`\`javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const OpenAI = require('openai');

admin.initializeApp();

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: functions.config().openai.api_key,
});

/**
 * Analyze document using OCR text only (privacy-first).
 * Callable function - requires authentication.
 */
exports.analyzeDocument = functions
  .region('europe-west1') // GDPR compliance - EU region
  .runWith({
    timeoutSeconds: 60,
    memory: '512MB',
  })
  .https.onCall(async (data, context) => {
    // Verify authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated to use AI analysis'
      );
    }

    // Validate input
    const { ocrText, documentType, languageHints, currencyHints } = data;

    if (!ocrText || typeof ocrText !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'OCR text is required'
      );
    }

    // Verify user has Pro subscription (implement your subscription check)
    // const hasPro = await checkSubscription(context.auth.uid);
    // if (!hasPro) {
    //   throw new functions.https.HttpsError(
    //     'permission-denied',
    //     'Pro subscription required for AI analysis'
    //   );
    // }

    try {
      // Call OpenAI with structured prompt
      const completion = await openai.chat.completions.create({
        model: functions.config().openai.model || 'gpt-4o',
        temperature: 0.1, // Low temperature for consistent extraction
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: buildSystemPrompt(documentType, languageHints, currencyHints),
          },
          {
            role: 'user',
            content: ocrText,
          },
        ],
      });

      // Parse response
      const result = JSON.parse(completion.choices[0].message.content);

      // Log usage (for cost tracking, no PII)
      functions.logger.info('AI analysis completed', {
        userId: context.auth.uid,
        tokensUsed: completion.usage.total_tokens,
        model: completion.model,
      });

      // Return structured result
      return {
        vendorName: result.vendor_name || null,
        vendorAddress: result.vendor_address || null,
        vendorNIP: result.vendor_nip || null,
        amount: result.amount || null,
        issueDate: result.issue_date || null,
        dueDate: result.due_date || null,
        documentNumber: result.document_number || null,
        bankAccount: result.bank_account || null,

        // Candidates for alternatives UI
        vendorCandidates: buildCandidates(result.vendor_candidates),
        nipCandidates: buildCandidates(result.nip_candidates),
        amountCandidates: buildCandidates(result.amount_candidates),
        dateCandidates: buildCandidates(result.date_candidates),
        documentNumberCandidates: buildCandidates(result.document_number_candidates),
        bankAccountCandidates: buildCandidates(result.bank_account_candidates),
      };
    } catch (error) {
      functions.logger.error('OpenAI API error', {
        error: error.message,
        userId: context.auth.uid,
      });

      throw new functions.https.HttpsError(
        'internal',
        'Failed to analyze document with AI',
        error.message
      );
    }
  });

/**
 * Build system prompt for OpenAI based on document type and hints.
 */
function buildSystemPrompt(documentType, languageHints, currencyHints) {
  const languages = languageHints?.join(' and ') || 'Polish and English';
  const currencies = currencyHints?.join(', ') || 'PLN, EUR, USD';

  return \`You are an expert invoice and document parser. Extract structured data from OCR text.

Languages: ${languages}
Expected currencies: ${currencies}
Document type: ${documentType || 'invoice'}

Extract the following fields with HIGH CONFIDENCE:
1. vendor_name: Company or seller name
2. vendor_address: Full address (street, city, postal code)
3. vendor_nip: Polish Tax ID (10 digits, format: XXXXXXXXXX)
4. amount: Total amount to pay (look for "do zapłaty", "total", "amount due")
5. issue_date: Invoice issue date (ISO 8601 format: YYYY-MM-DD)
6. due_date: Payment due date (ISO 8601 format: YYYY-MM-DD)
7. document_number: Invoice/document number
8. bank_account: Bank account for payment (IBAN or Polish 26-digit)

Also provide ALTERNATIVES (candidates) for each field with confidence scores 0.0-1.0:
- vendor_candidates: Array of {displayValue, confidence, evidenceBBox}
- nip_candidates: Array of {displayValue, confidence}
- amount_candidates: Array of {displayValue, confidence}
- date_candidates: Array of {displayValue, confidence}
- document_number_candidates: Array of {displayValue, confidence}
- bank_account_candidates: Array of {displayValue, confidence}

CRITICAL RULES:
- For amounts, prioritize "do zapłaty" (amount due) over "brutto" or "razem"
- For dates, look for context: "termin płatności" = due date, "data wystawienia" = issue date
- Return null for fields you're not confident about (don't guess)
- Return JSON only, no markdown or explanation
- evidenceBBox is optional (null if unavailable)

Return valid JSON matching this schema:
{
  "vendor_name": "string or null",
  "vendor_address": "string or null",
  "vendor_nip": "string or null",
  "amount": "number or null",
  "issue_date": "YYYY-MM-DD or null",
  "due_date": "YYYY-MM-DD or null",
  "document_number": "string or null",
  "bank_account": "string or null",
  "vendor_candidates": [{displayValue, confidence}],
  "nip_candidates": [{displayValue, confidence}],
  "amount_candidates": [{displayValue, confidence}],
  "date_candidates": [{displayValue, confidence}],
  "document_number_candidates": [{displayValue, confidence}],
  "bank_account_candidates": [{displayValue, confidence}]
}\`;
}

/**
 * Build candidate array from OpenAI response.
 */
function buildCandidates(candidates) {
  if (!Array.isArray(candidates)) return [];

  return candidates.map(c => ({
    displayValue: c.displayValue || c.value || '',
    confidence: typeof c.confidence === 'number' ? c.confidence : 0.5,
    extractionMethod: 'cloudAI',
    evidenceBBox: c.evidenceBBox || null,
  }));
}

/**
 * Get subscription status for user.
 * Callable function - requires authentication.
 */
exports.getSubscriptionStatus = functions
  .region('europe-west1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    // TODO: Implement actual subscription check with StoreKit server-side verification
    // For now, return free tier
    return {
      status: 'free',
      expiresAt: null,
      willAutoRenew: false,
      productId: null,
      originalPurchaseDate: null,
      isTrialPeriod: false,
      isInGracePeriod: false,
    };
  });
\`\`\`

## Step 4: Set Environment Variables

```bash
# Set OpenAI API key
firebase functions:config:set openai.api_key="sk-proj-YOUR_API_KEY_HERE"

# Set OpenAI model (gpt-4o recommended for accuracy)
firebase functions:config:set openai.model="gpt-4o"

# Verify config
firebase functions:config:get
```

**Security**: Never commit API keys. Use Firebase Functions config or Secret Manager.

## Step 5: Deploy Functions

```bash
# Deploy all functions
firebase deploy --only functions

# Or deploy specific function
firebase deploy --only functions:analyzeDocument
```

Expected output:
```
✔  functions[analyzeDocument(europe-west1)]: Successful create operation.
Function URL: https://europe-west1-your-project.cloudfunctions.net/analyzeDocument
```

## Step 6: Test the Function

### Test from iOS app:

The `FirebaseCloudExtractionGateway` will automatically call the deployed function when Pro tier users analyze documents with low local confidence.

### Test manually with curl:

```bash
# Get auth token from Firebase Auth
# (This requires an authenticated user - use Firebase Auth REST API or SDK)

curl -X POST \
  https://europe-west1-your-project.cloudfunctions.net/analyzeDocument \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "ocrText": "FAKTURA VAT\\nSprzedawca: ACME Corp\\nNIP: 1234567890\\nDo zapłaty: 1234.56 PLN\\nTermin płatności: 2026-02-15",
      "documentType": "invoice",
      "languageHints": ["pl", "en"],
      "currencyHints": ["PLN"]
    }
  }'
```

## Step 7: Monitor and Optimize

### View Logs

```bash
firebase functions:log --only analyzeDocument
```

### Monitor Costs

- **Firebase Functions**: https://console.firebase.google.com/project/your-project/functions/usage
- **OpenAI API**: https://platform.openai.com/usage

### Cost Optimization Tips

1. **Use GPT-4o-mini for non-critical documents** (~90% cheaper than GPT-4o)
2. **Cache common vendor patterns** (reduce API calls)
3. **Set per-user rate limits** (prevent abuse)
4. **Use local analysis first** (only call OpenAI on low confidence)

### Expected Costs

Per document analyzed:
- **GPT-4o**: ~$0.01-0.02 (high accuracy, recommended)
- **GPT-4o-mini**: ~$0.001-0.002 (good accuracy, budget-friendly)
- **Firebase Functions**: ~$0.0002 (included in free tier)

Monthly cost for 100 Pro users averaging 20 documents/month:
- **Scenario 1** (GPT-4o): ~$40/month
- **Scenario 2** (GPT-4o-mini): ~$4/month

## Security Best Practices

### 1. Authentication

```javascript
// Verify user is authenticated
if (!context.auth) {
  throw new functions.https.HttpsError('unauthenticated', 'Login required');
}
```

### 2. Rate Limiting

```javascript
// Example: Limit to 100 requests per user per day
const userRef = admin.firestore().collection('usage').doc(context.auth.uid);
const usage = await userRef.get();
const today = new Date().toISOString().split('T')[0];

if (usage.exists && usage.data().date === today && usage.data().count >= 100) {
  throw new functions.https.HttpsError('resource-exhausted', 'Daily limit exceeded');
}
```

### 3. Input Validation

```javascript
// Validate OCR text length (prevent abuse)
if (ocrText.length > 50000) {
  throw new functions.https.HttpsError('invalid-argument', 'Text too long');
}
```

### 4. No PII in Logs

```javascript
// ✅ GOOD: Log metrics only
functions.logger.info('Analysis completed', {
  userId: context.auth.uid, // Hashed internally by Firebase
  tokensUsed: completion.usage.total_tokens,
});

// ❌ BAD: Never log actual content
// functions.logger.info('Analyzing', { ocrText, amount, vendorName });
```

## Troubleshooting

### "Firebase CLI not found"
```bash
npm install -g firebase-tools
firebase --version
```

### "OpenAI API key not set"
```bash
firebase functions:config:set openai.api_key="sk-..."
firebase deploy --only functions
```

### "Function timeout"
```javascript
// Increase timeout in function options
.runWith({
  timeoutSeconds: 120, // Max: 540 (9 minutes)
  memory: '1GB',
})
```

### "CORS error from iOS"

Cloud Functions automatically handle CORS for callable functions. If using HTTP functions, add:

```javascript
const cors = require('cors')({ origin: true });

exports.myFunction = functions.https.onRequest((req, res) => {
  cors(req, res, () => {
    // Your function logic
  });
});
```

## Next Steps

1. **Implement subscription verification** (StoreKit server-side validation)
2. **Add monitoring and alerts** (Firebase Cloud Monitoring)
3. **Optimize prompts** for better accuracy
4. **Add support for other document types** (receipts, contracts)
5. **Implement vendor template caching** (reduce API calls for recurring vendors)

## Support

- Firebase Functions docs: https://firebase.google.com/docs/functions
- OpenAI API docs: https://platform.openai.com/docs
- DuEasy issues: https://github.com/your-repo/dueasy/issues
