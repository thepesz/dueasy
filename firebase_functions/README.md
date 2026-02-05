# DuEasy Cloud Functions

Backend functions for DuEasy - AI-powered document analysis using OpenAI GPT-4o.

## Privacy Guarantee

**DuEasy NEVER uploads images or PDFs to the cloud.**

All document processing follows this strict privacy-first flow:
1. Images/PDFs are processed locally on-device using Apple Vision OCR
2. Only the extracted TEXT is sent to cloud for AI analysis
3. Original documents NEVER leave the user's device

This is a core privacy commitment with no exceptions or fallbacks.

## Features

- **Privacy-First**: Only processes OCR text, NEVER images or PDFs
- **High Accuracy**: GPT-4o achieves 99%+ accuracy on invoice extraction
- **Rate Limited**: Free tier: 3/month, Pro tier: 100/month
- **GDPR Compliant**: Deployed in EU region (europe-west1)
- **Cost Optimized**: Smart routing only uses cloud when needed

## Functions

### `analyzeDocument`
Analyzes OCR text to extract invoice fields. This is the ONLY analysis endpoint.

**Input:**
```json
{
  "ocrText": "FAKTURA VAT...",
  "documentType": "invoice",
  "languageHints": ["pl", "en"],
  "currencyHints": ["PLN", "EUR"]
}
```

**Output:**
```json
{
  "vendorName": "ACME Corp",
  "vendorNIP": "1234567890",
  "amount": "1234.56",
  "dueDate": "2026-02-15",
  "vendorCandidates": [{displayValue, confidence}, ...],
  ...
}
```

### `getSubscriptionStatus`
Returns user's subscription status and entitlements.

### `restorePurchases`
Validates and restores previous App Store purchases.

## Setup

### 1. Install Dependencies

```bash
cd firebase_functions
npm install
```

### 2. Configure Environment

```bash
# Copy example env file
cp .env.example .env

# Edit .env and add your OpenAI API key
nano .env
```

### 3. Set Firebase Config

```bash
# Set OpenAI API key
firebase functions:config:set openai.api_key="sk-proj-YOUR_KEY"
firebase functions:config:set openai.model="gpt-4o"

# Verify
firebase functions:config:get
```

### 4. Deploy

```bash
# Deploy all functions
firebase deploy --only functions

# Or deploy specific function
firebase deploy --only functions:analyzeDocument
```

## Local Testing

### Start Emulator

```bash
npm run serve
```

The emulator will start on `http://localhost:5001`

### Test with curl

```bash
curl -X POST http://localhost:5001/YOUR-PROJECT/europe-west1/analyzeDocument \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "ocrText": "FAKTURA VAT\\nNIP: 1234567890\\nDo zapłaty: 1234.56 PLN",
      "documentType": "invoice",
      "languageHints": ["pl"],
      "currencyHints": ["PLN"]
    }
  }'
```

## Monitoring

### View Logs

```bash
# Real-time logs
firebase functions:log --only analyzeDocument

# Filter by severity
firebase functions:log --only analyzeDocument --severity ERROR
```

### Monitor Usage

- **Firebase Console**: https://console.firebase.google.com/project/YOUR-PROJECT/functions/usage
- **OpenAI Usage**: https://platform.openai.com/usage

## Cost Analysis

### Per Request

| Model | Input Cost | Output Cost | Avg Total |
|-------|-----------|-------------|-----------|
| gpt-4o | $2.50/1M tokens | $10.00/1M tokens | ~$0.01-0.02 |
| gpt-4o-mini | $0.15/1M tokens | $0.60/1M tokens | ~$0.001-0.002 |

Typical invoice: ~1500 input tokens, ~500 output tokens

### Monthly (100 Pro Users, 20 docs/month each)

- **GPT-4o**: ~$40/month (~$0.40/user)
- **GPT-4o-mini**: ~$4/month (~$0.04/user)
- **Firebase Functions**: Free tier covers it (2M invocations/month)

## Rate Limits

Default limits (per user):
- **Hourly**: 20 requests
- **Daily**: 100 requests

Limits are enforced in-memory and reset on cold starts.

To change limits, edit in `index.js`:
```javascript
const RATE_LIMIT_PER_DAY = 100;
const RATE_LIMIT_PER_HOUR = 20;
```

## Security

### Authentication

All functions require Firebase Authentication:
```javascript
if (!auth) {
  throw new HttpsError('unauthenticated', 'Login required');
}
```

### Subscription Verification

Cloud functions verify Pro subscription before processing:
```javascript
const hasPro = await checkProSubscription(auth.uid);
if (!hasPro) {
  throw new HttpsError('permission-denied', 'Pro subscription required');
}
```

### Input Validation

- OCR text length: Max 100,000 characters
- No image upload endpoints exist (privacy by design)

### Privacy

**No PII in logs:**
```javascript
// ✅ GOOD
console.log('Analysis completed', {
  userId: auth.uid, // Firebase hashes this
  tokensUsed: 2000,
});

// ❌ BAD - Never log
console.log({vendorName, amount, invoiceText});
```

## Troubleshooting

### "OpenAI API key not found"

```bash
# Check config
firebase functions:config:get

# Set if missing
firebase functions:config:set openai.api_key="sk-..."
```

### "Rate limit exceeded"

User hit hourly/daily limit. Wait or increase limits in code.

### "Permission denied"

User doesn't have Pro subscription. Check Firestore `users/{uid}/subscription.tier`.

### "Invalid JSON response"

OpenAI sometimes returns markdown. The code handles this but you can:
1. Lower temperature (already at 0.1)
2. Add more explicit instructions in system prompt
3. Retry with exponential backoff

## Production Checklist

- [ ] OpenAI API key set in Firebase config
- [ ] Functions deployed to europe-west1 (GDPR)
- [ ] Rate limiting tested and appropriate
- [ ] Subscription verification working
- [ ] Cost alerts set up in GCP
- [ ] Error monitoring configured
- [ ] Logs reviewed for PII leaks
- [ ] Backup/restore procedures documented

## Support

- Firebase Functions: https://firebase.google.com/docs/functions
- OpenAI API: https://platform.openai.com/docs
- DuEasy Issues: https://github.com/your-repo/dueasy/issues
