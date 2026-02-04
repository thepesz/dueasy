# RevenueCat Subscription Integration

This document describes the production-ready RevenueCat subscription integration for DuEasy.

## Overview

The integration replaces testing/mock subscription logic with production-ready implementation:

- **iOS**: RevenueCat SDK for subscription management, entitlement checking, and purchases
- **Backend**: RevenueCat API integration with monthly usage enforcement
- **Monetization**: Proper rate limiting with upgrade prompts

## Architecture

### iOS Components

1. **RevenueCatConfiguration.swift**
   - API key configuration
   - Entitlement and product IDs
   - Monthly limit constants

2. **RevenueCatSubscriptionService.swift**
   - Implements `SubscriptionServiceProtocol`
   - Handles purchases via RevenueCat SDK
   - Real-time entitlement updates via delegate
   - Restore purchases support

3. **AppEnvironment.swift**
   - Dynamic tier based on subscription status
   - Subscription status observation
   - Automatic cache updates on status changes

4. **SubscriptionPaywallView.swift**
   - Fetches offerings from RevenueCat
   - Handles purchase flow
   - Error handling with user feedback

### Backend Components

1. **usageCounter.js**
   - Monthly usage tracking in Firestore
   - Atomic check-and-increment operations
   - Automatic reset at month boundary

2. **revenueCat.js**
   - RevenueCat API integration
   - Entitlement verification with caching
   - Firestore fallback when API unavailable
   - Webhook handler for subscription events

3. **index.js**
   - Monthly limit enforcement
   - Usage info in API responses
   - RevenueCat webhook endpoint

## Configuration

### iOS Setup

1. Add RevenueCat SDK to your Xcode project:
   ```
   File -> Add Package Dependencies
   URL: https://github.com/RevenueCat/purchases-ios.git
   Version: 4.0.0 or later
   ```

2. Configure API key in `RevenueCatConfiguration.swift`:
   ```swift
   static let apiKey = "appl_YOUR_PUBLIC_API_KEY_HERE"
   ```

3. Configure entitlements in RevenueCat dashboard:
   - Create "pro" entitlement
   - Link monthly/yearly products to "pro" entitlement

### Backend Setup

1. Set RevenueCat API key:
   ```bash
   firebase functions:config:set revenuecat.api_key="YOUR_SECRET_API_KEY"
   ```

2. Optionally set webhook secret:
   ```bash
   firebase functions:config:set revenuecat.webhook_secret="YOUR_WEBHOOK_SECRET"
   ```

3. Deploy functions:
   ```bash
   cd firebase_functions
   npm install
   firebase deploy --only functions
   ```

4. Configure RevenueCat webhook (optional but recommended):
   - URL: `https://europe-west1-YOUR_PROJECT.cloudfunctions.net/revenueCatWebhook`
   - Events: INITIAL_PURCHASE, RENEWAL, EXPIRATION, CANCELLATION

### App Store Connect Setup

Create subscription products:
- `com.dueasy.pro.monthly` - Monthly Pro subscription
- `com.dueasy.pro.yearly` - Yearly Pro subscription

## Usage Limits

| Tier | Monthly Cloud Extractions |
|------|--------------------------|
| Free | 3                        |
| Pro  | 100                      |

## Rate Limit Flow

1. User initiates document scan
2. iOS sends OCR text to `analyzeDocument` function
3. Backend checks monthly usage via `checkAndIncrementUsage()`
4. If limit exceeded:
   - Returns `resource-exhausted` error with usage details
   - iOS shows upgrade banner + falls back to local extraction
5. If within limit:
   - Increments usage count
   - Processes with OpenAI
   - Returns results with usage info

## Error Handling

### iOS

Rate limit errors result in local fallback with upgrade banner:
```swift
case .rateLimitExceeded(let used, let limit, let resetDate):
    // Fall back to local but show banner
    let localResult = try await localService.analyze(...)
    return localResult.withRateLimitFallback(used: used, limit: limit, resetDate: resetDate)
```

### Backend

Usage is decremented on processing failures to avoid charging users for failed attempts.

## Testing

### iOS Testing

1. **Free tier (no purchase)**:
   - App works normally
   - After 3 extractions: Rate limit banner + upgrade option

2. **Purchase Pro**:
   - RevenueCat sandbox purchase flow
   - Entitlement activated
   - Limit increases to 100/month

3. **Restore purchases**:
   - Tap "Restore Purchases"
   - Entitlement restored if valid

### Backend Testing

Use Firebase emulator for local testing:
```bash
firebase emulators:start --only functions,firestore
```

Test rate limiting:
```javascript
// Free user, 4th extraction (should fail)
const result = await analyzeDocument({ocrText: "..."});
// Expected: resource-exhausted error
```

## Files Changed

### New Files
- `/Dueasy_v2/App/RevenueCatConfiguration.swift`
- `/Dueasy_v2/Services/Subscription/RevenueCatSubscriptionService.swift`
- `/firebase_functions/usageCounter.js`
- `/firebase_functions/revenueCat.js`

### Modified Files
- `/Dueasy_v2/App/AppEnvironment.swift` - Dynamic tier from subscription
- `/Dueasy_v2/App/DuEasyApp.swift` - RevenueCat SDK initialization
- `/Dueasy_v2/Features/Subscription/Views/SubscriptionPaywallView.swift` - Real purchase flow
- `/firebase_functions/index.js` - Usage enforcement + RevenueCat integration

## Security Considerations

1. **iOS API Key**: Use public SDK key only (safe to include in app)
2. **Backend API Key**: Use secret key, stored in Firebase config
3. **Webhook Secret**: Verify webhook authenticity
4. **Caching**: 5-minute TTL to balance performance and freshness
5. **Firestore Fallback**: Ensures service continuity if RevenueCat API unavailable

## Monitoring

Track these metrics in Firebase/RevenueCat:
- Daily/monthly extraction counts by tier
- Rate limit hit rate
- Conversion from rate limit to upgrade
- API error rates
