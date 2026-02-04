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
 * @param {string} uid - Firebase user ID
 * @returns {Promise<{count: number, limit: number, tier: string}>} Current usage info
 */
async function getUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  const db = admin.firestore();
  const usageDoc = await db.collection('usage').doc(usageKey).get();

  const currentCount = usageDoc.exists ? (usageDoc.data().count || 0) : 0;
  const tier = await getUserTier(uid);
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
 * @param {string} uid - Firebase user ID
 * @returns {Promise<{allowed: boolean, used: number, limit: number, tier: string, resetDate?: Date, error?: Object}>}
 */
async function checkAndIncrementUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  const db = admin.firestore();
  const usageRef = db.collection('usage').doc(usageKey);

  // Get user's tier and limit
  const tier = await getUserTier(uid);
  const limit = MONTHLY_LIMITS[tier] || MONTHLY_LIMITS.free;

  // Use a transaction for atomic check-and-increment
  const result = await db.runTransaction(async (transaction) => {
    const usageDoc = await transaction.get(usageRef);
    const currentCount = usageDoc.exists ? (usageDoc.data().count || 0) : 0;

    // Check if limit exceeded
    if (currentCount >= limit) {
      const resetDate = calculateResetDate();

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

    // Increment usage
    const newCount = currentCount + 1;
    transaction.set(usageRef, {
      count: newCount,
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
      userId: uid,
      monthKey: monthKey,
    }, {merge: true});

    return {
      allowed: true,
      used: newCount,
      limit: limit,
      tier: tier,
      remaining: limit - newCount,
    };
  });

  console.log('Usage check result', {
    userId: uid,
    tier: result.tier,
    used: result.used,
    limit: result.limit,
    allowed: result.allowed,
  });

  return result;
}

/**
 * Decrement usage count (used for rollback on failed operations).
 *
 * @param {string} uid - Firebase user ID
 * @returns {Promise<void>}
 */
async function decrementUsage(uid) {
  const monthKey = getMonthKey();
  const usageKey = `usage:${uid}:${monthKey}`;

  const db = admin.firestore();
  const usageRef = db.collection('usage').doc(usageKey);

  await db.runTransaction(async (transaction) => {
    const usageDoc = await transaction.get(usageRef);
    if (usageDoc.exists) {
      const currentCount = usageDoc.data().count || 0;
      if (currentCount > 0) {
        transaction.update(usageRef, {
          count: currentCount - 1,
          lastDecremented: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  });

  console.log('Usage decremented for user:', uid);
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

  const db = admin.firestore();
  await db.collection('usage').doc(usageKey).delete();

  console.log('Usage reset for user:', uid, 'month:', key);
}

/**
 * Get usage history for a user (for analytics/support).
 *
 * @param {string} uid - Firebase user ID
 * @param {number} [monthsBack=6] - Number of months of history to retrieve
 * @returns {Promise<Array<{month: string, count: number}>>}
 */
async function getUsageHistory(uid, monthsBack = 6) {
  const db = admin.firestore();
  const history = [];

  const now = new Date();

  for (let i = 0; i < monthsBack; i++) {
    const date = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const monthKey = `${year}-${month}`;
    const usageKey = `usage:${uid}:${monthKey}`;

    const usageDoc = await db.collection('usage').doc(usageKey).get();
    const count = usageDoc.exists ? (usageDoc.data().count || 0) : 0;

    history.push({
      month: monthKey,
      count: count,
    });
  }

  return history;
}

module.exports = {
  checkAndIncrementUsage,
  decrementUsage,
  resetUsage,
  getUsage,
  getUsageHistory,
  getMonthKey,
  calculateResetDate,
  MONTHLY_LIMITS,
};
