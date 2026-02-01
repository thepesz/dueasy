const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

const userId = 'wisOjM8nqQd1rzdlHCATrExy8al2';

async function setProSubscription() {
  try {
    await admin.firestore()
      .collection('users')
      .doc(userId)
      .set({
        subscription: {
          tier: 'pro',
          isActive: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        }
      }, { merge: true });

    console.log('✅ Pro subscription set for user:', userId);

    // Verify it was set
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();

    console.log('📄 User document:', JSON.stringify(userDoc.data(), null, 2));

    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

setProSubscription();
