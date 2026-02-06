/**
 * Monthly usage counter for cloud extraction limits.
 *
 * Tracks and enforces monthly extraction limits per user:
 * - Free tier: 3 extractions/month
 * - Pro tier: 100 extractions/month
 *
 * Usage is stored in Firestore with month-based keys for automatic reset.
 * This module is the single source of truth for limit enforcement.
 */

const admin = require('firebase-admin');
const {getUserTier} = require('./revenueCat');

// Monthly limits by tier
const MONTHLY_LIMITS = {
  free: 3,
  pro: 100,
};

/**
 * Get the current month key in format: YYYY-MM
 * @returns {string} Month key for Firestore document ID
 */
function getMonthKey() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

/**
 * Calculate the reset date (first day of next month at midnight UTC)
 * @returns {Date} Reset date
 */
function calculateResetDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();

  // First day of next month
  const nextMonth = month === 11 ? 0 : month + 1;
  const nextYear = month === 11 ? year + 1 : year;

  return new Date(Date.UTC(nextYear, nextMonth, 1, 0, 0, 0, 0));
}

/**
 * Get current usage for a user this month.
 *
 * IMPORTANT: This function handles all Firestore errors gracefully.
 * It will never throw - returns default values on any error.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<{count: number, limit: number, tier: string}>} Current usage info
 */
async function getUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  let currentCount = 0;

  // Safely get usage document
  try {
    const db = admin.firestore();
    const usageDoc = await db.collection('usage').doc(usageKey).get();
    if (usageDoc && usageDoc.exists) {
      const data = usageDoc.data();
      currentCount = (data && data.count) || 0;
    }
  } catch (usageError) {
    console.log('Error fetching usage document (defaulting to 0):', usageError?.message);
    currentCount = 0;
  }

  // Get tier with fallback to 'free' on any error
  let tier = 'free';
  try {
    tier = await getUserTier(uid);
  } catch (error) {
    console.warn('Error getting user tier in getUsage, defaulting to free:', error?.message);
    tier = 'free';
  }

  const limit = MONTHLY_LIMITS[tier] || MONTHLY_LIMITS.free;

  return {
    count: currentCount,
    limit: limit,
    tier: tier,
  };
}

/**
 * Check if user can make another extraction and increment count if allowed.
 *
 * This is an atomic operation - it checks and increments in one transaction
 * to prevent race conditions when user makes multiple rapid requests.
 *
 * IMPORTANT: This function now logs detailed errors but still fails-open for UX.
 * Set USAGE_FAIL_CLOSED=true environment variable to fail-closed for testing.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<{allowed: boolean, used: number, limit: number, tier: string, resetDate?: Date, error?: Object}>}
 */
async function checkAndIncrementUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  console.log('[UsageCounter] Starting check for:', {uid, monthKey, usageKey});

  // Get user's tier and limit with fallback to 'free' on any error
  // This MUST be outside the transaction to avoid nested async issues
  let tier = 'free';
  try {
    tier = await getUserTier(uid);
    console.log('[UsageCounter] Got user tier:', tier);
  } catch (error) {
    console.warn('[UsageCounter] Error getting user tier, defaulting to free:', {
      error: error?.message,
      code: error?.code,
    });
    tier = 'free';
  }
  const limit = MONTHLY_LIMITS[tier] || MONTHLY_LIMITS.free;

  // Wrap entire transaction in try-catch for robustness
  let result;
  let transactionError = null;

  try {
    const db = admin.firestore();
    const usageRef = db.collection('usage').doc(usageKey);

    console.log('[UsageCounter] Starting Firestore transaction for:', usageKey);

    // Use a transaction for atomic check-and-increment
    // CRITICAL: Do NOT catch errors inside the transaction - let them propagate
    result = await db.runTransaction(async (transaction) => {
      // Read current usage - if doc doesn't exist, that's fine (count = 0)
      const usageDoc = await transaction.get(usageRef);

      let currentCount = 0;
      if (usageDoc.exists) {
        const data = usageDoc.data();
        currentCount = (data && data.count) || 0;
        console.log('[UsageCounter] Existing usage doc found, count:', currentCount);
      } else {
        console.log('[UsageCounter] No existing usage doc, starting at 0');
      }

      // Check if limit exceeded
      if (currentCount >= limit) {
        const resetDate = calculateResetDate();
        console.log('[UsageCounter] Limit exceeded:', {currentCount, limit});

        // Return early - no write needed
        return {
          allowed: false,
          used: currentCount,
          limit: limit,
          tier: tier,
          error: {
            code: 'limit_exceeded',
            data: {
              used: currentCount,
              limit: limit,
              tier: tier,
              resetDateISO: resetDate.toISOString(),
            },
          },
        };
      }

      // Increment usage - use set with merge to create doc if it doesn't exist
      const newCount = currentCount + 1;
      console.log('[UsageCounter] Incrementing usage from', currentCount, 'to', newCount);

      transaction.set(usageRef, {
        count: newCount,
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        userId: uid,
        monthKey: monthKey,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      console.log('[UsageCounter] Transaction set() called, returning result');

      return {
        allowed: true,
        used: newCount,
        limit: limit,
        tier: tier,
        remaining: limit - newCount,
      };
    });

    console.log('[UsageCounter] Transaction completed successfully:', result);
  } catch (error) {
    // Capture detailed error information
    transactionError = {
      message: error?.message,
      code: error?.code,
      details: error?.details,
      stack: error?.stack?.substring(0, 500),
    };

    console.error('[UsageCounter] TRANSACTION FAILED - DETAILED ERROR:', transactionError);

    // Check if we should fail-closed (for testing) or fail-open (for production UX)
    const failClosed = process.env.USAGE_FAIL_CLOSED === 'true';

    if (failClosed) {
      // Fail-closed: Block the request so we can debug
      console.error('[UsageCounter] FAIL_CLOSED mode - blocking request');
      result = {
        allowed: false,
        used: 0,
        limit: limit,
        tier: tier,
        error: {
          code: 'transaction_failed',
          data: {
            message: 'Usage tracking failed. Please try again.',
            debugInfo: transactionError,
          },
        },
        transactionFailed: true,
      };
    } else {
      // Fail-open: Allow the request (better UX, but usage not tracked)
      console.warn('[UsageCounter] FAIL_OPEN mode - allowing request despite error');
      result = {
        allowed: true,
        used: 0,
        limit: limit,
        tier: tier,
        remaining: limit,
        transactionFailed: true,
        transactionErrorDetails: transactionError,
      };
    }
  }

  console.log('[UsageCounter] Final result:', {
    userId: uid,
    tier: result.tier,
    used: result.used,
    limit: result.limit,
    allowed: result.allowed,
    transactionFailed: result.transactionFailed || false,
  });

  return result;
}

/**
 * Decrement usage count (used for rollback on failed operations).
 *
 * IMPORTANT: This function handles all Firestore errors gracefully.
 * It will never throw - just logs and continues on any error.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<void>}
 */
async function decrementUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  try {
    const db = admin.firestore();
    const usageRef = db.collection('usage').doc(usageKey);

    await db.runTransaction(async (transaction) => {
      let currentCount = 0;
      try {
        const usageDoc = await transaction.get(usageRef);
        if (usageDoc && usageDoc.exists) {
          const data = usageDoc.data();
          currentCount = (data && data.count) || 0;
        }
      } catch (getError) {
        console.log('Error reading usage doc in decrement, skipping:', getError?.message);
        return; // Exit transaction without changes
      }

      if (currentCount > 0) {
        transaction.update(usageRef, {
          count: currentCount - 1,
          lastDecremented: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    console.log('Usage decremented for user:', uid);
  } catch (error) {
    // Don't throw - decrement is best-effort
    console.warn('Failed to decrement usage (non-critical):', error?.message);
  }
}

/**
 * Reset usage for a user (admin function for testing or support).
 *
 * @param {string} uid - Firebase user ID
 * @param {string} [monthKey] - Optional month key, defaults to current month
 * @returns {Promise<void>}
 */
async function resetUsage(uid, monthKey = null) {
  const key = monthKey || getMonthKey();
  const usageKey = `usage:${uid}:${key}`;

  try {
    const db = admin.firestore();
    await db.collection('usage').doc(usageKey).delete();
    console.log('Usage reset for user:', uid, 'month:', key);
  } catch (error) {
    console.warn('Failed to reset usage:', error?.message);
    // Don't throw - admin operations should be resilient
  }
}

/**
 * Get usage history for a user (for analytics/support).
 *
 * @param {string} uid - Firebase user ID
 * @param {number} [monthsBack=6] - Number of months of history to retrieve
 * @returns {Promise<Array<{month: string, count: number}>>}
 */
async function getUsageHistory(uid, monthsBack = 6) {
  const history = [];
  const now = new Date();

  try {
    const db = admin.firestore();

    for (let i = 0; i < monthsBack; i++) {
      const date = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const monthKey = `${year}-${month}`;
      const usageKey = `usage:${uid}:${monthKey}`;

      let count = 0;
      try {
        const usageDoc = await db.collection('usage').doc(usageKey).get();
        if (usageDoc && usageDoc.exists) {
          const data = usageDoc.data();
          count = (data && data.count) || 0;
        }
      } catch (docError) {
        console.log('Error fetching usage for month', monthKey, ':', docError?.message);
        count = 0;
      }

      history.push({
        month: monthKey,
        count: count,
      });
    }
  } catch (error) {
    console.warn('Failed to get usage history:', error?.message);
    // Return empty history on error
  }

  return history;
}

/**
 * Diagnostic function to test Firestore write permissions.
 * Call this to verify the backend can write to the usage collection.
 *
 * @param {string} uid - Firebase user ID to test with
 * @returns {Promise<{success: boolean, error?: Object, testDocId?: string}>}
 */
async function testFirestoreWrite(uid) {
  const testDocId = `test:${uid}:${Date.now()}`;

  console.log('[UsageCounter] Testing Firestore write with doc:', testDocId);

  try {
    const db = admin.firestore();
    const testRef = db.collection('usage').doc(testDocId);

    // Test 1: Simple write (no transaction)
    console.log('[UsageCounter] Test 1: Simple write...');
    await testRef.set({
      test: true,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      userId: uid,
    });
    console.log('[UsageCounter] Test 1: Simple write SUCCESS');

    // Test 2: Read it back
    console.log('[UsageCounter] Test 2: Read back...');
    const doc = await testRef.get();
    if (!doc.exists) {
      throw new Error('Document was written but cannot be read back');
    }
    console.log('[UsageCounter] Test 2: Read back SUCCESS, data:', doc.data());

    // Test 3: Transaction write
    console.log('[UsageCounter] Test 3: Transaction write...');
    await db.runTransaction(async (transaction) => {
      const currentDoc = await transaction.get(testRef);
      transaction.set(testRef, {
        test: true,
        transactionTest: true,
        count: (currentDoc.data()?.count || 0) + 1,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    console.log('[UsageCounter] Test 3: Transaction write SUCCESS');

    // Test 4: Verify transaction write persisted
    console.log('[UsageCounter] Test 4: Verify transaction persisted...');
    const finalDoc = await testRef.get();
    const finalData = finalDoc.data();
    if (!finalData?.transactionTest) {
      throw new Error('Transaction write did not persist');
    }
    console.log('[UsageCounter] Test 4: Transaction persisted SUCCESS, data:', finalData);

    // Cleanup test document
    await testRef.delete();
    console.log('[UsageCounter] Test document cleaned up');

    return {
      success: true,
      testDocId: testDocId,
      message: 'All Firestore write tests passed',
    };
  } catch (error) {
    console.error('[UsageCounter] Firestore write test FAILED:', {
      message: error?.message,
      code: error?.code,
      details: error?.details,
    });

    return {
      success: false,
      testDocId: testDocId,
      error: {
        message: error?.message,
        code: error?.code,
        details: error?.details,
      },
    };
  }
}

/**
 * Direct increment without transaction (for debugging).
 * Use this if transactions are failing but you need usage tracking.
 *
 * WARNING: This is NOT atomic and may have race conditions.
 * Only use for testing or as a last resort.
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<{success: boolean, newCount?: number, error?: Object}>}
 */
async function directIncrementUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  console.log('[UsageCounter] Direct increment (non-transactional) for:', usageKey);

  try {
    const db = admin.firestore();
    const usageRef = db.collection('usage').doc(usageKey);

    // Use FieldValue.increment for atomic increment without transaction
    await usageRef.set({
      count: admin.firestore.FieldValue.increment(1),
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
      userId: uid,
      monthKey: monthKey,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    // Read back to verify
    const doc = await usageRef.get();
    const data = doc.data();

    console.log('[UsageCounter] Direct increment SUCCESS, new count:', data?.count);

    return {
      success: true,
      newCount: data?.count,
    };
  } catch (error) {
    console.error('[UsageCounter] Direct increment FAILED:', {
      message: error?.message,
      code: error?.code,
    });

    return {
      success: false,
      error: {
        message: error?.message,
        code: error?.code,
      },
    };
  }
}

module.exports = {
  checkAndIncrementUsage,
  decrementUsage,
  resetUsage,
  getUsage,
  getUsageHistory,
  getMonthKey,
  calculateResetDate,
  testFirestoreWrite,
  directIncrementUsage,
  MONTHLY_LIMITS,
};
