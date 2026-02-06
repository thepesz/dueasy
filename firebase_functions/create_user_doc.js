const admin = require('firebase-admin');
admin.initializeApp();

const uid = '2qBzF9oOBBbxPDSzsFVMTcXdMLh2';

admin.firestore()
  .collection('users')
  .doc(uid)
  .set({
    subscription: {
      tier: 'free',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true })
  .then(() => {
    console.log('User document created successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Error creating user document:', error);
    process.exit(1);
  });
