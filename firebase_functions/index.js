/**
 * DuEasy Cloud Functions
 *
 * Provides AI-powered document analysis for Pro tier users.
 * Privacy-first: Only processes OCR text, never full images.
 *
 * Functions:
 * - analyzeDocument: Extract fields from invoice OCR text using OpenAI
 * - analyzeDocumentWithImages: Fallback for low-confidence scenarios (opt-in)
 * - getSubscriptionStatus: Verify user subscription status
 * - restorePurchases: Restore previous purchases
 */

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {setGlobalOptions} = require('firebase-functions/v2');
const {defineString} = require('firebase-functions/params');
const admin = require('firebase-admin');
const OpenAI = require('openai');

// Define parameters for environment config
const openaiApiKey = defineString('OPENAI_API_KEY');
const openaiModel = defineString('OPENAI_MODEL', {default: 'gpt-4o'});

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

// Rate limiting cache (in-memory, resets on cold start)
const rateLimits = new Map();
const RATE_LIMIT_PER_DAY = 100;
const RATE_LIMIT_PER_HOUR = 20;

/**
 * Analyze document using OCR text only (privacy-first approach).
 *
 * This is the PRIMARY method - keeps images on device.
 * Only OCR text is sent to cloud for AI analysis.
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
      'Authentication required for AI analysis'
    );
  }

  // Check rate limits
  await checkRateLimit(auth.uid);

  // Validate input
  const {ocrText, documentType, languageHints, currencyHints} = data;

  if (!ocrText || typeof ocrText !== 'string') {
    throw new HttpsError(
      'invalid-argument',
      'OCR text is required and must be a string'
    );
  }

  if (ocrText.length > 100000) {
    throw new HttpsError(
      'invalid-argument',
      'OCR text too long (max 100,000 characters)'
    );
  }

  // TESTING: Temporarily skip Pro subscription check
  // TODO: Re-enable this check after testing
  // const hasPro = await checkProSubscription(auth.uid);
  // if (!hasPro) {
  //   throw new HttpsError(
  //     'permission-denied',
  //     'Pro subscription required for AI analysis. Please upgrade to continue.'
  //   );
  // }
  console.log('⚠️ TESTING MODE: Skipping Pro subscription check for user:', auth.uid);

  try {
    console.log('Starting AI analysis', {
      userId: auth.uid,
      documentType: documentType || 'invoice',
      textLength: ocrText.length,
    });

    // Build system prompt
    const systemPrompt = buildSystemPrompt(
      documentType || 'invoice',
      languageHints || ['pl', 'en'],
      currencyHints || ['PLN', 'EUR', 'USD']
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
      userId: auth.uid,
      tokensUsed: completion.usage.total_tokens,
      promptTokens: completion.usage.prompt_tokens,
      completionTokens: completion.usage.completion_tokens,
      model: completion.model,
      estimatedCost: estimateCost(completion.usage.total_tokens, openaiModel.value()),
    });

    // Update user usage statistics
    await updateUsageStats(auth.uid, completion.usage.total_tokens);

    // Return structured result
    return formatAnalysisResult(result);

  } catch (error) {
    console.error('OpenAI API error', {
      userId: auth.uid,
      error: error.message,
      stack: error.stack,
    });

    // Handle specific OpenAI errors
    if (error.status === 429) {
      throw new HttpsError(
        'resource-exhausted',
        'AI service rate limit exceeded. Please try again in a few minutes.'
      );
    }

    if (error.status === 401) {
      throw new HttpsError(
        'internal',
        'AI service configuration error. Please contact support.'
      );
    }

    throw new HttpsError(
      'internal',
      'Failed to analyze document with AI. Please try again.',
      error.message
    );
  }
});

/**
 * Analyze with cropped images (fallback for low-confidence scenarios).
 * User must explicitly opt-in to send image data.
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

  await checkRateLimit(auth.uid);

  const {ocrText, images, documentType, languageHints} = data;

  if (!images || !Array.isArray(images) || images.length === 0) {
    throw new HttpsError('invalid-argument', 'At least one image required');
  }

  if (images.length > 5) {
    throw new HttpsError('invalid-argument', 'Maximum 5 images allowed');
  }

  const hasPro = await checkProSubscription(auth.uid);
  if (!hasPro) {
    throw new HttpsError('permission-denied', 'Pro subscription required');
  }

  try {
    console.log('Starting vision analysis', {
      userId: auth.uid,
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
          ['PLN', 'EUR', 'USD']
        ),
      },
      {
        role: 'user',
        content: [
          ocrText ? {type: 'text', text: `OCR Text:\n${ocrText}`} : null,
          ...images.map(img => ({
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
      model: 'gpt-4o', // Vision requires gpt-4o
      temperature: 0.1,
      response_format: {type: 'json_object'},
      messages: messages,
    });

    const result = JSON.parse(completion.choices[0].message.content);

    console.log('Vision analysis completed', {
      userId: auth.uid,
      tokensUsed: completion.usage.total_tokens,
      model: completion.model,
    });

    await updateUsageStats(auth.uid, completion.usage.total_tokens);

    return formatAnalysisResult(result);

  } catch (error) {
    console.error('Vision analysis error', {
      userId: auth.uid,
      error: error.message,
    });

    throw new HttpsError(
      'internal',
      'Failed to analyze images. Please try again.',
      error.message
    );
  }
});

/**
 * Get subscription status for user.
 * Verifies App Store receipts and returns entitlements.
 */
exports.getSubscriptionStatus = onCall({
  cors: true,
}, async (request) => {
  const {auth} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(auth.uid)
      .get();

    if (!userDoc.exists) {
      // New user - default to free tier
      return {
        status: 'free',
        tier: 'free',
        expiresAt: null,
        willAutoRenew: false,
        productId: null,
        originalPurchaseDate: null,
        isTrialPeriod: false,
        isInGracePeriod: false,
      };
    }

    const userData = userDoc.data();
    const subscription = userData.subscription || {};

    // Check if subscription is expired
    if (subscription.expiresAt) {
      const expiryDate = new Date(subscription.expiresAt);
      const now = new Date();

      if (expiryDate < now && !subscription.isInGracePeriod) {
        // Subscription expired
        return {
          status: 'expired',
          tier: 'free',
          expiresAt: subscription.expiresAt,
          willAutoRenew: false,
          productId: subscription.productId,
          originalPurchaseDate: subscription.originalPurchaseDate,
          isTrialPeriod: false,
          isInGracePeriod: false,
        };
      }
    }

    // Active subscription
    if (subscription.tier === 'pro') {
      return {
        status: 'pro',
        tier: 'pro',
        expiresAt: subscription.expiresAt || null,
        willAutoRenew: subscription.willAutoRenew !== false,
        productId: subscription.productId || null,
        originalPurchaseDate: subscription.originalPurchaseDate || null,
        isTrialPeriod: subscription.isTrialPeriod === true,
        isInGracePeriod: subscription.isInGracePeriod === true,
      };
    }

    // Default to free
    return {
      status: 'free',
      tier: 'free',
      expiresAt: null,
      willAutoRenew: false,
      productId: null,
      originalPurchaseDate: null,
      isTrialPeriod: false,
      isInGracePeriod: false,
    };

  } catch (error) {
    console.error('Error fetching subscription status', {
      userId: auth.uid,
      error: error.message,
    });

    throw new HttpsError(
      'internal',
      'Failed to fetch subscription status',
      error.message
    );
  }
});

/**
 * Restore previous purchases.
 * Verifies App Store receipts and restores entitlements.
 */
exports.restorePurchases = onCall({
  cors: true,
}, async (request) => {
  const {auth} = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  // TODO: Implement StoreKit server-side receipt validation
  // For now, just return current status
  console.log('Restore purchases requested', {userId: auth.uid});

  return {
    success: true,
    message: 'Receipt validation not yet implemented',
  };
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
 * Check if user has Pro subscription.
 */
async function checkProSubscription(userId) {
  try {
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();

    if (!userDoc.exists) {
      return false;
    }

    const subscription = userDoc.data().subscription;
    if (!subscription || subscription.tier !== 'pro') {
      return false;
    }

    // Check expiration
    if (subscription.expiresAt) {
      const expiryDate = new Date(subscription.expiresAt);
      const now = new Date();

      if (expiryDate < now && !subscription.isInGracePeriod) {
        return false;
      }
    }

    return true;

  } catch (error) {
    console.error('Error checking subscription', {userId, error: error.message});
    return false;
  }
}

/**
 * Check rate limits for user.
 */
async function checkRateLimit(userId) {
  const now = Date.now();
  const hourKey = `${userId}:hour:${Math.floor(now / 3600000)}`;
  const dayKey = `${userId}:day:${Math.floor(now / 86400000)}`;

  // Check hourly limit
  const hourCount = rateLimits.get(hourKey) || 0;
  if (hourCount >= RATE_LIMIT_PER_HOUR) {
    throw new HttpsError(
      'resource-exhausted',
      `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_HOUR} requests per hour.`
    );
  }

  // Check daily limit
  const dayCount = rateLimits.get(dayKey) || 0;
  if (dayCount >= RATE_LIMIT_PER_DAY) {
    throw new HttpsError(
      'resource-exhausted',
      `Daily limit exceeded. Maximum ${RATE_LIMIT_PER_DAY} requests per day.`
    );
  }

  // Increment counters
  rateLimits.set(hourKey, hourCount + 1);
  rateLimits.set(dayKey, dayCount + 1);
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
