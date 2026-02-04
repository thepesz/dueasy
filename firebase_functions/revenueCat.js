/**
 * RevenueCat integration for backend entitlement verification.
 *
 * Queries RevenueCat API to verify user subscription status.
 * Uses in-memory caching to reduce API calls and latency.
 *
 * Setup:
 * 1. Get your RevenueCat secret API key from dashboard
 * 2. Set Firebase config: firebase functions:config:set revenuecat.api_key="YOUR_SECRET_KEY"
 * 3. Optionally set project_id: firebase functions:config:set revenuecat.project_id="YOUR_PROJECT_ID"
 */

const {defineString} = require('firebase-functions/params');
const admin = require('firebase-admin');

// Define RevenueCat API key as a secret parameter
const revenueCatApiKey = defineString('REVENUECAT_API_KEY', {default: ''});

// Cache configuration
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes cache TTL
const entitlementCache = new Map();

// RevenueCat API configuration
const REVENUECAT_API_BASE = 'https://api.revenuecat.com/v1';
const PRO_ENTITLEMENT_ID = 'pro';

/**
 * Verify user's subscription tier via RevenueCat API.
 *
 * @param {string} uid - Firebase user ID (used as RevenueCat app_user_id)
 * @returns {Promise<'free'|'pro'>} User's subscription tier
 */
async function getUserTier(uid) {
  // Check cache first
  const cached = entitlementCache.get(uid);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    console.log('RevenueCat cache hit for user:', uid, 'tier:', cached.tier);
    return cached.tier;
  }

  try {
    const apiKey = revenueCatApiKey.value();

    // If no API key configured, fall back to Firestore-based subscription check
    if (!apiKey) {
      console.log('RevenueCat API key not configured, falling back to Firestore');
      return await getFirestoreTier(uid);
    }

    // Query RevenueCat Subscriber API
    const response = await fetch(
        `${REVENUECAT_API_BASE}/subscribers/${uid}`,
        {
          method: 'GET',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'X-Platform': 'ios',
          },
        },
    );

    // Handle non-200 responses
    if (!response.ok) {
      // 404 means user doesn't exist in RevenueCat - they're free tier
      if (response.status === 404) {
        console.log('User not found in RevenueCat, defaulting to free:', uid);
        cacheResult(uid, 'free');
        return 'free';
      }

      // Log other errors but don't throw
      console.error('RevenueCat API error:', response.status, response.statusText);

      // Fall back to Firestore on API error
      return await getFirestoreTier(uid);
    }

    const data = await response.json();

    // Check for active "pro" entitlement
    const entitlements = data.subscriber?.entitlements || {};
    const proEntitlement = entitlements[PRO_ENTITLEMENT_ID];

    // Check if entitlement exists and is active
    const hasProEntitlement = proEntitlement &&
      (proEntitlement.expires_date === null || // Lifetime
       new Date(proEntitlement.expires_date) > new Date()); // Not expired

    const tier = hasProEntitlement ? 'pro' : 'free';

    // Cache the result
    cacheResult(uid, tier);

    console.log('RevenueCat tier check:', {
      userId: uid,
      tier: tier,
      hasEntitlement: !!proEntitlement,
      expiresDate: proEntitlement?.expires_date || null,
    });

    return tier;
  } catch (error) {
    console.error('Failed to check RevenueCat entitlement:', error);

    // Fall back to Firestore on any error
    return await getFirestoreTier(uid);
  }
}

/**
 * Cache entitlement result with timestamp.
 *
 * @param {string} uid - User ID
 * @param {'free'|'pro'} tier - User tier
 */
function cacheResult(uid, tier) {
  entitlementCache.set(uid, {
    tier: tier,
    timestamp: Date.now(),
  });

  // Clean up old cache entries periodically
  if (entitlementCache.size > 1000) {
    cleanupCache();
  }
}

/**
 * Clean up expired cache entries.
 */
function cleanupCache() {
  const now = Date.now();
  for (const [uid, entry] of entitlementCache.entries()) {
    if (now - entry.timestamp > CACHE_TTL_MS * 2) {
      entitlementCache.delete(uid);
    }
  }
}

/**
 * Invalidate cache for a specific user.
 * Call this when subscription status might have changed.
 *
 * @param {string} uid - User ID to invalidate
 */
function invalidateCache(uid) {
  entitlementCache.delete(uid);
  console.log('RevenueCat cache invalidated for user:', uid);
}

/**
 * Fallback: Get user tier from Firestore subscription document.
 * Used when RevenueCat API is unavailable or not configured.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<'free'|'pro'>} User tier
 */
async function getFirestoreTier(uid) {
  try {
    const userDoc = await admin.firestore()
        .collection('users')
        .doc(uid)
        .get();

    if (!userDoc.exists) {
      return 'free';
    }

    const subscription = userDoc.data().subscription;
    if (!subscription || subscription.tier !== 'pro') {
      return 'free';
    }

    // Check expiration if present
    if (subscription.expiresAt) {
      const expiryDate = new Date(subscription.expiresAt);
      const now = new Date();

      if (expiryDate < now && !subscription.isInGracePeriod) {
        return 'free';
      }
    }

    return 'pro';
  } catch (error) {
    console.error('Error fetching Firestore subscription:', error);
    return 'free';
  }
}

/**
 * Get full subscription details for a user.
 * Returns more detailed information than getUserTier.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<Object>} Subscription details
 */
async function getSubscriptionDetails(uid) {
  try {
    const apiKey = revenueCatApiKey.value();

    if (!apiKey) {
      // No RevenueCat key, return basic info from Firestore
      const tier = await getFirestoreTier(uid);
      return {
        tier: tier,
        isActive: tier === 'pro',
        source: 'firestore',
      };
    }

    const response = await fetch(
        `${REVENUECAT_API_BASE}/subscribers/${uid}`,
        {
          method: 'GET',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'X-Platform': 'ios',
          },
        },
    );

    if (!response.ok) {
      const tier = await getFirestoreTier(uid);
      return {
        tier: tier,
        isActive: tier === 'pro',
        source: 'firestore-fallback',
        error: `RevenueCat API error: ${response.status}`,
      };
    }

    const data = await response.json();
    const subscriber = data.subscriber || {};
    const entitlements = subscriber.entitlements || {};
    const proEntitlement = entitlements[PRO_ENTITLEMENT_ID];

    const isActive = proEntitlement &&
      (proEntitlement.expires_date === null ||
       new Date(proEntitlement.expires_date) > new Date());

    return {
      tier: isActive ? 'pro' : 'free',
      isActive: isActive,
      source: 'revenuecat',
      entitlement: proEntitlement ? {
        expiresDate: proEntitlement.expires_date,
        purchaseDate: proEntitlement.purchase_date,
        productIdentifier: proEntitlement.product_identifier,
        isSandbox: proEntitlement.is_sandbox,
        willRenew: proEntitlement.will_renew,
        periodType: proEntitlement.period_type,
        ownershipType: proEntitlement.ownership_type,
      } : null,
      subscriptions: Object.keys(subscriber.subscriptions || {}),
      firstSeen: subscriber.first_seen,
      lastSeen: subscriber.last_seen,
    };
  } catch (error) {
    console.error('Failed to get subscription details:', error);
    const tier = await getFirestoreTier(uid);
    return {
      tier: tier,
      isActive: tier === 'pro',
      source: 'firestore-fallback',
      error: error.message,
    };
  }
}

/**
 * RevenueCat webhook handler for subscription events.
 * Updates Firestore and invalidates cache when subscription changes.
 *
 * @param {Object} event - RevenueCat webhook event
 * @returns {Promise<void>}
 */
async function handleWebhookEvent(event) {
  const eventType = event.type;
  const appUserId = event.app_user_id;

  console.log('RevenueCat webhook event:', {
    type: eventType,
    userId: appUserId,
  });

  // Invalidate cache for this user
  if (appUserId) {
    invalidateCache(appUserId);

    // Update Firestore subscription record
    const isProActive = ['INITIAL_PURCHASE', 'RENEWAL', 'PRODUCT_CHANGE']
        .includes(eventType);

    const isProExpired = ['EXPIRATION', 'CANCELLATION']
        .includes(eventType);

    if (isProActive || isProExpired) {
      await admin.firestore()
          .collection('users')
          .doc(appUserId)
          .set({
            subscription: {
              tier: isProActive ? 'pro' : 'free',
              lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
              lastEventType: eventType,
              productId: event.product_id || null,
              expiresAt: event.expiration_at_ms ?
                new Date(event.expiration_at_ms).toISOString() : null,
            },
          }, {merge: true});

      console.log('Firestore subscription updated:', {
        userId: appUserId,
        tier: isProActive ? 'pro' : 'free',
        eventType: eventType,
      });
    }
  }
}

module.exports = {
  getUserTier,
  getSubscriptionDetails,
  invalidateCache,
  handleWebhookEvent,
  PRO_ENTITLEMENT_ID,
};
