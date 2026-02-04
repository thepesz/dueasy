/**
 * DuEasy Cloud Functions
 *
 * Provides AI-powered document analysis for all users with tier-based limits.
 * Privacy-first: Only processes OCR text, never full images.
 *
 * Functions:
 * - analyzeDocument: Extract fields from invoice OCR text using OpenAI
 * - analyzeDocumentWithImages: Fallback for low-confidence scenarios (opt-in)
 * - getSubscriptionStatus: Verify user subscription status via RevenueCat
 * - getUsageInfo: Get current usage and limit info
 * - revenueCatWebhook: Handle RevenueCat subscription events
 */

const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {setGlobalOptions} = require('firebase-functions/v2');
const {defineString} = require('firebase-functions/params');
const admin = require('firebase-admin');
const OpenAI = require('openai');

// Import usage and subscription modules
const {checkAndIncrementUsage, decrementUsage, getUsage, MONTHLY_LIMITS} = require('./usageCounter');
const {getUserTier, getSubscriptionDetails, handleWebhookEvent, invalidateCache} = require('./revenueCat');

// Define parameters for environment config
const openaiApiKey = defineString('OPENAI_API_KEY');
const openaiModel = defineString('OPENAI_MODEL', {default: 'gpt-4o-mini'});
const revenueCatWebhookSecret = defineString('REVENUECAT_WEBHOOK_SECRET', {default: ''});

// Initialize Firebase Admin
admin.initializeApp();

// Global options - EU region for GDPR compliance
setGlobalOptions({
  region: 'europe-west1',
  maxInstances: 10,
});

// Lazy initialization of OpenAI client
let openai;
function getOpenAIClient() {
  if (!openai) {
    openai = new OpenAI({
      apiKey: openaiApiKey.value(),
    });
  }
  return openai;
}

/**
 * Analyze document using OCR text only (privacy-first approach).
 *
 * This is the PRIMARY method - keeps images on device.
 * Only OCR text is sent to cloud for AI analysis.
 *
 * Rate limiting:
 * - Free tier: 3 extractions/month
 * - Pro tier: 100 extractions/month
 *
 * @param {Object} data - Request data
 * @param {string} data.ocrText - Pre-extracted OCR text
 * @param {string} data.documentType - Document type (invoice, receipt, etc.)
 * @param {string[]} data.languageHints - Languages expected (e.g., ["pl", "en"])
 * @param {string[]} data.currencyHints - Currencies expected (e.g., ["PLN", "EUR"])
 * @returns {Promise<Object>} Structured analysis result
 */
exports.analyzeDocument = onCall({
  timeoutSeconds: 60,
  memory: '512MiB',
  cors: true,
}, async (request) => {
  const {auth, data} = request;

  // Verify authentication
  if (!auth) {
    throw new HttpsError(
        'unauthenticated',
        'Authentication required for AI analysis',
    );
  }

  const uid = auth.uid;

  // Check and increment monthly usage limit
  const usageResult = await checkAndIncrementUsage(uid);

  if (!usageResult.allowed) {
    // Monthly limit exceeded - return structured error for iOS paywall
    console.log('Rate limit exceeded for user:', uid, usageResult.error.data);

    throw new HttpsError(
        'resource-exhausted',
        'Monthly extraction limit exceeded',
        usageResult.error.data, // { used, limit, tier, resetDateISO }
    );
  }

  // Validate input
  const {ocrText, documentType, languageHints, currencyHints} = data;

  if (!ocrText || typeof ocrText !== 'string') {
    // Decrement usage since we're not processing
    await decrementUsage(uid);
    throw new HttpsError(
        'invalid-argument',
        'OCR text is required and must be a string',
    );
  }

  if (ocrText.length > 100000) {
    // Decrement usage since we're not processing
    await decrementUsage(uid);
    throw new HttpsError(
        'invalid-argument',
        'OCR text too long (max 100,000 characters)',
    );
  }

  try {
    console.log('Starting AI analysis', {
      userId: uid,
      tier: usageResult.tier,
      used: usageResult.used,
      limit: usageResult.limit,
      remaining: usageResult.remaining,
      documentType: documentType || 'invoice',
      textLength: ocrText.length,
    });

    // Build system prompt
    const systemPrompt = buildSystemPrompt(
        documentType || 'invoice',
        languageHints || ['pl', 'en'],
        currencyHints || ['PLN', 'EUR', 'USD'],
    );

    // Call OpenAI
    const completion = await getOpenAIClient().chat.completions.create({
      model: openaiModel.value(),
      temperature: 0.1, // Low temperature for consistent extraction
      response_format: {type: 'json_object'},
      messages: [
        {
          role: 'system',
          content: systemPrompt,
        },
        {
          role: 'user',
          content: ocrText,
        },
      ],
    });

    // Parse OpenAI response
    const result = JSON.parse(completion.choices[0].message.content);

    // Log usage for cost tracking (no PII)
    console.log('AI analysis completed', {
      userId: uid,
      tier: usageResult.tier,
      tokensUsed: completion.usage.total_tokens,
      promptTokens: completion.usage.prompt_tokens,
      completionTokens: completion.usage.completion_tokens,
      model: completion.model,
      estimatedCost: estimateCost(completion.usage.total_tokens, openaiModel.value()),
    });

    // Update user usage statistics
    await updateUsageStats(uid, completion.usage.total_tokens);

    // Return structured result with usage info
    const analysisResult = formatAnalysisResult(result);
    analysisResult.usageInfo = {
      used: usageResult.used,
      limit: usageResult.limit,
      remaining: usageResult.remaining,
      tier: usageResult.tier,
    };

    return analysisResult;
  } catch (error) {
    // Decrement usage on failure so user isn't charged for failed attempt
    await decrementUsage(uid);

    console.error('OpenAI API error', {
      userId: uid,
      error: error.message,
      stack: error.stack,
    });

    // Handle specific OpenAI errors
    if (error.status === 429) {
      throw new HttpsError(
          'resource-exhausted',
          'AI service rate limit exceeded. Please try again in a few minutes.',
      );
    }

    if (error.status === 401) {
      throw new HttpsError(
          'internal',
          'AI service configuration error. Please contact support.',
      );
    }

    throw new HttpsError(
        'internal',
        'Failed to analyze document with AI. Please try again.',
        error.message,
    );
  }
});

/**
 * Analyze with cropped images (fallback for low-confidence scenarios).
 * User must explicitly opt-in to send image data.
 * Pro subscription required for image analysis.
 *
 * @param {Object} data - Request data
 * @param {string} data.ocrText - OCR text (may be null)
 * @param {string[]} data.images - Base64-encoded cropped images
 * @param {string} data.documentType - Document type
 * @param {string[]} data.languageHints - Languages expected
 * @returns {Promise<Object>} Structured analysis result
 */
exports.analyzeDocumentWithImages = onCall({
  timeoutSeconds: 120,
  memory: '1GiB',
  cors: true,
}, async (request) => {
  const {auth, data} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = auth.uid;

  // Check usage limit
  const usageResult = await checkAndIncrementUsage(uid);
  if (!usageResult.allowed) {
    throw new HttpsError(
        'resource-exhausted',
        'Monthly extraction limit exceeded',
        usageResult.error.data,
    );
  }

  // Image analysis requires Pro subscription
  const tier = await getUserTier(uid);
  if (tier !== 'pro') {
    await decrementUsage(uid);
    throw new HttpsError(
        'permission-denied',
        'Pro subscription required for image analysis',
    );
  }

  const {ocrText, images, documentType, languageHints} = data;

  if (!images || !Array.isArray(images) || images.length === 0) {
    await decrementUsage(uid);
    throw new HttpsError('invalid-argument', 'At least one image required');
  }

  if (images.length > 5) {
    await decrementUsage(uid);
    throw new HttpsError('invalid-argument', 'Maximum 5 images allowed');
  }

  try {
    console.log('Starting vision analysis', {
      userId: uid,
      imageCount: images.length,
      hasOcrText: !!ocrText,
    });

    // Build vision messages
    const messages = [
      {
        role: 'system',
        content: buildSystemPrompt(
            documentType || 'invoice',
            languageHints || ['pl', 'en'],
            ['PLN', 'EUR', 'USD'],
        ),
      },
      {
        role: 'user',
        content: [
          ocrText ? {type: 'text', text: `OCR Text:\n${ocrText}`} : null,
          ...images.map((img) => ({
            type: 'image_url',
            image_url: {
              url: `data:image/jpeg;base64,${img}`,
              detail: 'high',
            },
          })),
        ].filter(Boolean),
      },
    ];

    // Call OpenAI Vision
    const completion = await getOpenAIClient().chat.completions.create({
      model: 'gpt-4o-mini',
      temperature: 0.1,
      response_format: {type: 'json_object'},
      messages: messages,
    });

    const result = JSON.parse(completion.choices[0].message.content);

    console.log('Vision analysis completed', {
      userId: uid,
      tokensUsed: completion.usage.total_tokens,
      model: completion.model,
    });

    await updateUsageStats(uid, completion.usage.total_tokens);

    const analysisResult = formatAnalysisResult(result);
    analysisResult.usageInfo = {
      used: usageResult.used,
      limit: usageResult.limit,
      remaining: usageResult.remaining,
      tier: usageResult.tier,
    };

    return analysisResult;
  } catch (error) {
    await decrementUsage(uid);

    console.error('Vision analysis error', {
      userId: uid,
      error: error.message,
    });

    throw new HttpsError(
        'internal',
        'Failed to analyze images. Please try again.',
        error.message,
    );
  }
});

/**
 * Get subscription status for user via RevenueCat.
 */
exports.getSubscriptionStatus = onCall({
  cors: true,
}, async (request) => {
  const {auth} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    const details = await getSubscriptionDetails(auth.uid);
    const usage = await getUsage(auth.uid);

    return {
      status: details.tier,
      tier: details.tier,
      isActive: details.isActive,
      expiresAt: details.entitlement?.expiresDate || null,
      willAutoRenew: details.entitlement?.willRenew || false,
      productId: details.entitlement?.productIdentifier || null,
      originalPurchaseDate: details.entitlement?.purchaseDate || null,
      isTrialPeriod: details.entitlement?.periodType === 'trial',
      isInGracePeriod: details.entitlement?.periodType === 'grace',
      source: details.source,
      usage: {
        used: usage.count,
        limit: usage.limit,
        remaining: usage.limit - usage.count,
      },
    };
  } catch (error) {
    console.error('Error fetching subscription status', {
      userId: auth.uid,
      error: error.message,
    });

    throw new HttpsError(
        'internal',
        'Failed to fetch subscription status',
        error.message,
    );
  }
});

/**
 * Get current usage information for user.
 */
exports.getUsageInfo = onCall({
  cors: true,
}, async (request) => {
  const {auth} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    const usage = await getUsage(auth.uid);

    return {
      used: usage.count,
      limit: usage.limit,
      remaining: usage.limit - usage.count,
      tier: usage.tier,
      limits: MONTHLY_LIMITS,
    };
  } catch (error) {
    console.error('Error fetching usage info', {
      userId: auth.uid,
      error: error.message,
    });

    throw new HttpsError(
        'internal',
        'Failed to fetch usage info',
        error.message,
    );
  }
});

/**
 * Restore previous purchases.
 * Invalidates cache and returns fresh subscription status.
 */
exports.restorePurchases = onCall({
  cors: true,
}, async (request) => {
  const {auth} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  // Invalidate cache to force fresh lookup
  invalidateCache(auth.uid);

  // Get fresh subscription details
  const details = await getSubscriptionDetails(auth.uid);

  console.log('Restore purchases requested', {
    userId: auth.uid,
    tier: details.tier,
  });

  return {
    success: true,
    tier: details.tier,
    isActive: details.isActive,
  };
});

/**
 * RevenueCat webhook endpoint for subscription events.
 * Updates local subscription state when RevenueCat notifies of changes.
 */
exports.revenueCatWebhook = onRequest({
  cors: false, // Webhooks don't need CORS
}, async (req, res) => {
  // Verify webhook secret if configured
  const secret = revenueCatWebhookSecret.value();
  if (secret) {
    const authHeader = req.headers['authorization'];
    if (authHeader !== `Bearer ${secret}`) {
      console.warn('RevenueCat webhook: Invalid authorization');
      res.status(401).send('Unauthorized');
      return;
    }
  }

  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }

  try {
    const event = req.body;

    if (!event || !event.type) {
      res.status(400).send('Invalid webhook payload');
      return;
    }

    await handleWebhookEvent(event);

    res.status(200).send('OK');
  } catch (error) {
    console.error('RevenueCat webhook error:', error);
    res.status(500).send('Internal error');
  }
});

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Build OpenAI system prompt for document analysis.
 */
function buildSystemPrompt(documentType, languageHints, currencyHints) {
  const languages = languageHints.join(' and ');
  const currencies = currencyHints.join(', ');

  return `You are an expert invoice and document parser. Extract structured data from OCR text with HIGH ACCURACY.

DOCUMENT CONTEXT:
- Type: ${documentType}
- Languages: ${languages}
- Currencies: ${currencies}

EXTRACTION TASK:
Extract these fields with maximum confidence:

1. vendor_name: Company/seller name (exact match from document)
2. vendor_address: Full address including street, city, postal code
3. vendor_nip: Polish Tax ID (10 digits, format: XXXXXXXXXX)
4. amount: Total amount to pay (the FINAL amount due, not subtotal)
5. issue_date: Invoice issue date (ISO 8601: YYYY-MM-DD)
6. due_date: Payment due date (ISO 8601: YYYY-MM-DD)
7. document_number: Invoice/document number (exact as printed)
8. bank_account: Bank account for payment (IBAN or Polish 26-digit)

CRITICAL RULES FOR VENDOR INFORMATION:
- Polish: Look for sections labeled "Sprzedawca", "Sprzedający", "Dostawca"
- English: Look for sections labeled "Seller", "Vendor", "From", "Supplier"
- PRIORITIZE vendor info from labeled sections (near "Sprzedawca"/"Seller" label)
- IGNORE vendor info from:
  * Stamps or seals (pieczątki)
  * Footer or signature areas
  * "Wystawił" (issued by) sections
  * Header logos or watermarks
- Vendor address should be complete: street + building number + postal code + city
- Example: "02-672 Warszawa, ul. Domaniewska 39"

CRITICAL RULES FOR AMOUNTS:
- Polish: "do zapłaty" = amount due (HIGHEST PRIORITY)
- Polish: "suma" or "razem" = total/subtotal (LOWER PRIORITY)
- Polish: "brutto" = gross amount (LOWER PRIORITY if deductions exist)
- English: "amount due", "total due", "balance due" (HIGHEST PRIORITY)
- English: "total", "grand total" (LOWER PRIORITY)
- ALWAYS prefer "amount due" / "do zapłaty" over other totals

CRITICAL RULES FOR DATES:
- Polish: "termin płatności", "płatne do" = due date
- Polish: "data wystawienia", "wystawiono" = issue date
- English: "due date", "payment due" = due date
- English: "issue date", "invoice date" = issue date
- If only one date, it's likely the issue date
- Due date is usually AFTER issue date

ALTERNATIVES (candidates):
For each field, provide alternative values with confidence 0.0-1.0:
- vendor_candidates: [{displayValue, confidence}]
- nip_candidates: [{displayValue, confidence}]
- amount_candidates: [{displayValue, confidence}] (include ALL amounts found with context)
- date_candidates: [{displayValue, confidence}]
- document_number_candidates: [{displayValue, confidence}]
- bank_account_candidates: [{displayValue, confidence}]

VALIDATION:
- vendor_name: Should be a company name, not empty
- vendor_nip: Exactly 10 digits (Polish NIP format)
- amount: Positive number, matches currency
- dates: Valid dates in YYYY-MM-DD format
- due_date: Should be >= issue_date
- bank_account: Valid IBAN or 26-digit Polish account

CONFIDENCE SCORING:
- 0.95-1.0: Explicit label found (e.g., "Do zapłaty: 1234.56")
- 0.80-0.94: Strong pattern match (e.g., amount in bottom-right)
- 0.60-0.79: Weak pattern or ambiguous
- 0.40-0.59: Guess based on structure
- Below 0.40: Very uncertain, might be wrong

OUTPUT FORMAT:
Return ONLY valid JSON (no markdown, no explanation):
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
}

IMPORTANT: If you cannot find a field with reasonable confidence, return null for that field. Never guess wildly.`;
}

/**
 * Format OpenAI response to match iOS DocumentAnalysisResult structure.
 */
function formatAnalysisResult(openaiResult) {
  return {
    vendorName: openaiResult.vendor_name || null,
    vendorAddress: openaiResult.vendor_address || null,
    vendorNIP: openaiResult.vendor_nip || null,
    amount: openaiResult.amount ? String(openaiResult.amount) : null,
    issueDate: openaiResult.issue_date || null,
    dueDate: openaiResult.due_date || null,
    documentNumber: openaiResult.document_number || null,
    bankAccount: openaiResult.bank_account || null,

    // Candidates
    vendorCandidates: buildCandidates(openaiResult.vendor_candidates),
    nipCandidates: buildCandidates(openaiResult.nip_candidates),
    amountCandidates: buildCandidates(openaiResult.amount_candidates),
    dateCandidates: buildCandidates(openaiResult.date_candidates),
    documentNumberCandidates: buildCandidates(openaiResult.document_number_candidates),
    bankAccountCandidates: buildCandidates(openaiResult.bank_account_candidates),
  };
}

/**
 * Build candidate array with confidence scores.
 */
function buildCandidates(candidates) {
  if (!Array.isArray(candidates)) return [];

  return candidates.map((c) => ({
    displayValue: c.displayValue || c.value || '',
    confidence: typeof c.confidence === 'number' ? c.confidence : 0.5,
    extractionMethod: 'cloudAI',
    evidenceBBox: c.evidenceBBox || null,
  }));
}

/**
 * Update user usage statistics.
 */
async function updateUsageStats(userId, tokensUsed) {
  try {
    const userRef = admin.firestore().collection('users').doc(userId);

    await userRef.set({
      usage: {
        lastAnalysis: admin.firestore.FieldValue.serverTimestamp(),
        totalAnalyses: admin.firestore.FieldValue.increment(1),
        totalTokens: admin.firestore.FieldValue.increment(tokensUsed),
      },
    }, {merge: true});
  } catch (error) {
    console.error('Error updating usage stats', {userId, error: error.message});
    // Don't throw - this is not critical
  }
}

/**
 * Estimate cost for OpenAI API call.
 */
function estimateCost(totalTokens, model) {
  // GPT-4o pricing (as of 2024)
  const pricePerMillionTokens = model === 'gpt-4o' ? 5.00 : 0.50; // gpt-4o-mini
  return (totalTokens / 1000000) * pricePerMillionTokens;
}
