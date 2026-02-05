'use client'

export default function PrivacyPage() {
  return (
    <div style={{ padding: '20px 0' }}>
      <style jsx global>{`
        body {
          font-size: 11px;
        }
        p, li {
          font-size: 11px;
          margin: 8px 0;
        }
        h1 {
          color: #1a1a1a;
          border-bottom: 2px solid #007AFF;
          padding-bottom: 8px;
          font-size: 1.4em;
          margin: 16px 0;
        }
        h2 {
          color: #007AFF;
          margin-top: 20px;
          margin-bottom: 12px;
          font-size: 1.1em;
        }
        .last-updated {
          color: #666;
          font-style: italic;
          font-size: 10px;
        }
        ul {
          line-height: 1.5;
          margin: 8px 0;
          padding-left: 20px;
        }
        a {
          color: #007AFF;
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
        @media (max-width: 600px) {
          body {
            font-size: 10px;
          }
          p, li {
            font-size: 10px;
          }
        }
      `}</style>
      
      <h1>PRIVACY POLICY</h1>
      <p className="last-updated">Last updated February 05, 2026</p>
      <p dangerouslySetInnerHTML={{ __html: `This Privacy Notice for DuEasy ( " we ," " us ," or " our " ), describes how and why we might access, collect, store, use, and/or share ( " process " ) your personal information when you use our services ( " Services " ), including when you:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Download and use our mobile application ( Dueasy) , or any other application of ours that links to this Privacy Notice` }} />
      <p dangerouslySetInnerHTML={{ __html: `Use DuEasy . AI based scan invoices app with automated reminder` }} />
      <p dangerouslySetInnerHTML={{ __html: `Engage with us in other related ways, including any marketing or events` }} />
      <p dangerouslySetInnerHTML={{ __html: `Questions or concerns?  Reading this Privacy Notice will help you understand your privacy rights and choices. We are responsible for making decisions about how your personal information is processed. If you do not agree with our policies and practices, please do not use our Services. If you still have any questions or concerns, please contact us at dueasy.sup@gmail.com .` }} />
      <h2>OUR PRIVACY-FIRST APPROACH</h2>
      <p dangerouslySetInnerHTML={{ __html: `DuEasy is built with privacy at its core. We collect only the minimum data necessary to provide our services:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `Your invoice images and PDFs are processed entirely on your device - we never upload them to our servers` }} />
        <li dangerouslySetInnerHTML={{ __html: `Only extracted text from invoices is sent to our cloud service for AI analysis (available on Free tier with monthly limits, or Pro tier with higher limits). Offline fallback uses on-device OCR and simple local parsing (no cloud AI)` }} />
        <li dangerouslySetInnerHTML={{ __html: `If you enable iCloud sync, your document data is stored in YOUR private iCloud account - we cannot access your iCloud data` }} />
        <li dangerouslySetInnerHTML={{ __html: `We do not use tracking or analytics for advertising purposes` }} />
        <li dangerouslySetInnerHTML={{ __html: `We do not collect browsing history, detailed usage patterns, or IP addresses for tracking` }} />
        <li dangerouslySetInnerHTML={{ __html: `Crash reports help us fix bugs but contain no personal or financial data from your documents` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `We believe your financial documents are private and should stay on your device. Our architecture reflects this commitment.` }} />
      <h2>SUMMARY OF KEY POINTS</h2>
      <p dangerouslySetInnerHTML={{ __html: `This summary provides key points from our Privacy Notice, but you can find out more details about any of these topics by clicking the link following each key point or by using our  table of contents  below to find the section you are looking for.` }} />
      <p dangerouslySetInnerHTML={{ __html: `What personal information do we process? When you visit, use, or navigate our Services, we may process personal information depending on how you interact with us and the Services, the choices you make, and the products and features you use. Learn more about  personal information you disclose to us .` }} />
      <p dangerouslySetInnerHTML={{ __html: `Do we process any sensitive personal information?  Some of the information may be considered "special" or "sensitive" in certain jurisdictions, for example your racial or ethnic origins, sexual orientation, and religious beliefs. We may process sensitive personal information when necessary with your consent or as otherwise permitted by applicable law. Learn more about  sensitive information we process .` }} />
      <p dangerouslySetInnerHTML={{ __html: `Do we purchase data from data brokers? We do not purchase personal data from data brokers or third parties. We use third-party service providers (Apple, Firebase, RevenueCat) to operate our app, as detailed in the "When and with whom we share" section.` }} />
      <p dangerouslySetInnerHTML={{ __html: `How do we process your information? We process your information to provide, improve, and administer our Services, communicate with you, for security and fraud prevention, and to comply with law. We may also process your information for other purposes with your consent. We process your information only when we have a valid legal reason to do so. Learn more about  how we process your information .` }} />
      <p dangerouslySetInnerHTML={{ __html: `In what situations and with which types of parties do we share personal information? We may share information in specific situations and with specific categories of third parties. Learn more about  when and with whom we share your personal information .` }} />
      <p dangerouslySetInnerHTML={{ __html: `How do we keep your information safe? We have adequate organizational and technical processes and procedures in place to protect your personal information. However, no electronic transmission over the internet or information storage technology can be guaranteed to be 100% secure, so we cannot promise or guarantee that hackers, cybercriminals, or other unauthorized third parties will not be able to defeat our security and improperly collect, access, steal, or modify your information. Learn more about  how we keep your information safe .` }} />
      <p dangerouslySetInnerHTML={{ __html: `What are your rights? Depending on where you are located geographically, the applicable privacy law may mean you have certain rights regarding your personal information. Learn more about  your privacy rights .` }} />
      <p dangerouslySetInnerHTML={{ __html: `How do you exercise your rights? The easiest way to exercise your rights is by visiting email: dueasy.sup@gmail.com , or by contacting us. We will consider and act upon any request in accordance with applicable data protection laws.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Want to learn more about what we do with any information we collect?  Review the Privacy Notice in full .` }} />
      <h2>TABLE OF CONTENTS</h2>
      <h2>1. WHAT INFORMATION DO WE COLLECT?</h2>
      <h2>2. HOW DO WE PROCESS YOUR INFORMATION?</h2>
      <h2>3. WHAT LEGAL BASES DO WE RELY ON TO PROCESS YOUR PERSONAL INFORMATION?</h2>
      <h2>4. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?</h2>
      <h2>5. DO WE OFFER ARTIFICIAL INTELLIGENCE-BASED PRODUCTS?</h2>
      <h2>6. IS YOUR INFORMATION TRANSFERRED INTERNATIONALLY?</h2>
      <h2>7. HOW LONG DO WE KEEP YOUR INFORMATION?</h2>
      <h2>8. HOW DO WE KEEP YOUR INFORMATION SAFE?</h2>
      <h2>9. DO WE COLLECT INFORMATION FROM MINORS?</h2>
      <h2>10. WHAT ARE YOUR PRIVACY RIGHTS?</h2>
      <h2>11. CONTROLS FOR DO-NOT-TRACK FEATURES</h2>
      <h2>12. DO UNITED STATES RESIDENTS HAVE SPECIFIC PRIVACY RIGHTS?</h2>
      <h2>13. DO WE MAKE UPDATES TO THIS NOTICE?</h2>
      <h2>14. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?</h2>
      <h2>15. HOW CAN YOU REVIEW, UPDATE, OR DELETE THE DATA WE COLLECT FROM YOU?</h2>
      <h2>1. WHAT INFORMATION DO WE COLLECT?</h2>
      <p dangerouslySetInnerHTML={{ __html: `Personal information you disclose to us` }} />
      <p dangerouslySetInnerHTML={{ __html: `In Short: We collect minimal information when you sign in with Apple, and information you provide when contacting support.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We collect personal information that you voluntarily provide to us when you sign in with Apple to use cloud analysis (optional), when you contact us for support, or when you participate in activities on the Services.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Sign in with Apple Authentication. When you sign in with Apple, we receive:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `An Apple user identifier (unique ID for your account)` }} />
        <li dangerouslySetInnerHTML={{ __html: `Optionally, an email address (which may be your real email or an Apple-provided relay address, depending on your Apple privacy settings)` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `You control what information Apple shares with us through your Apple ID settings. In many cases, we do not receive your actual email address.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Personal Information Provided by You. The personal information we collect may include the following:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Apple user identifier (required for authentication)` }} />
      <p dangerouslySetInnerHTML={{ __html: `email address (optional - may be real or Apple relay, depending on your Apple settings)` }} />
      <p dangerouslySetInnerHTML={{ __html: `Sensitive Information. When necessary, with your consent or as otherwise permitted by applicable law, we process the following categories of sensitive information:` }} />
      <p dangerouslySetInnerHTML={{ __html: `financial data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Payment Data. We do not receive your payment card details. All purchases are processed securely by Apple through in-app purchases. RevenueCat receives only your subscription status (active/expired) from Apple to manage your Pro features. Your payment information is never transmitted to us. For more details, see Apple's privacy policy: <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener noreferrer">https://www.apple.com/legal/privacy/</a> and RevenueCat's privacy policy: <a href="https://www.revenuecat.com/privacy/" target="_blank" rel="noopener noreferrer">https://www.revenuecat.com/privacy/</a>` }} />
      <p dangerouslySetInnerHTML={{ __html: `Application Data. If you use our application(s), we also may collect the following information if you choose to provide us with access or permission:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Mobile Device Access. We may request access or permission to certain features from your mobile device, including your mobile device's camera, calendar, photo gallery, and other features. If you wish to change our access or permissions, you may do so in your device's settings.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Mobile Device Data. We automatically collect minimal device information needed for app functionality: device model and manufacturer, operating system version, and app version. This information is used solely for crash reporting (via Firebase Crashlytics) to help us fix bugs. We do not collect IP addresses, browser information, ISP/carrier details, or detailed usage tracking for analytics purposes.` }} />
      <p dangerouslySetInnerHTML={{ __html: `This information is used solely for troubleshooting and service reliability monitoring (via crash reports).` }} />
      <p dangerouslySetInnerHTML={{ __html: `All personal information that you provide to us must be true, complete, and accurate, and you must notify us of any changes to such personal information.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Information automatically collected` }} />
      <p dangerouslySetInnerHTML={{ __html: `In Short: We collect minimal information required to provide the service and ensure app stability. This includes crash reports and basic authentication data.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We follow a privacy-first approach and collect only the minimum information necessary to provide and maintain our Services. We do not use tracking for advertising or behavioral analytics.` }} />
      <p dangerouslySetInnerHTML={{ __html: `The information we collect automatically includes:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Authentication Data. When you use cloud analysis (optional, with Free/Pro limits), we collect your authentication token and user ID to verify your account and provide secure access to cloud services.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Crash Reports and Diagnostics. We use Firebase Crashlytics to automatically collect crash reports when the app experiences errors. This helps us identify and fix bugs to improve app stability. Crash reports may include:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `Device model and operating system version` }} />
        <li dangerouslySetInnerHTML={{ __html: `App version and state at the time of crash` }} />
        <li dangerouslySetInnerHTML={{ __html: `Stack traces and error logs` }} />
        <li dangerouslySetInnerHTML={{ __html: `Available memory and storage at crash time` }} />
        <li dangerouslySetInnerHTML={{ __html: `Timestamp and crash location in code` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `These crash reports do not contain your personal documents, invoice data, or any sensitive information from your device.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Service Request Metadata. When you use cloud analysis (Free tier: limited monthly requests, Pro tier: higher limits), our servers log basic request information including:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `User ID (for rate limiting and authentication)` }} />
        <li dangerouslySetInnerHTML={{ __html: `Request timestamp and function name` }} />
        <li dangerouslySetInnerHTML={{ __html: `Error messages (no sensitive content)` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `We do not log IP addresses, browsing history, or detailed usage patterns. We do not use analytics tools for tracking user behavior.` }} />
      <h2>2. HOW DO WE PROCESS YOUR INFORMATION?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We process your information to provide, improve, and administer our Services, communicate with you, for security and fraud prevention, and to comply with law. We process the personal information for the following purposes listed below. We may also process your information for other purposes only with your prior explicit consent.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We process your personal information for a variety of reasons, depending on how you interact with our Services, including:` }} />
      <p dangerouslySetInnerHTML={{ __html: `To facilitate account creation and authentication and otherwise manage user accounts.  We may process your information so you can create and log in to your account, as well as keep your account in working order.` }} />
      <p dangerouslySetInnerHTML={{ __html: `To deliver and facilitate delivery of services to the user.  We may process your information to provide you with the requested service.` }} />
      <p dangerouslySetInnerHTML={{ __html: `To respond to user inquiries/offer support to users.  We may process your information to respond to your inquiries and solve any potential issues you might have with the requested service.` }} />
      <p dangerouslySetInnerHTML={{ __html: `To protect our Services. We may process your information as part of our efforts to keep our Services safe and secure, including fraud monitoring and prevention.` }} />
      <p dangerouslySetInnerHTML={{ __html: `To save or protect an individual's vital interest. We may process your information when necessary to save or protect an individual’s vital interest, such as to prevent harm.` }} />
      <h2>3. WHAT LEGAL BASES DO WE RELY ON TO PROCESS YOUR INFORMATION?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We only process your personal information when we believe it is necessary and we have a valid legal reason (i.e. , legal basis) to do so under applicable law, like with your consent, to comply with laws, to provide you with services to enter into or fulfill our contractual obligations, to protect your rights, or to fulfill our legitimate business interests.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you are located in the EU or UK, this section applies to you.` }} />
      <p dangerouslySetInnerHTML={{ __html: `The General Data Protection Regulation (GDPR) and UK GDPR require us to explain the valid legal bases we rely on in order to process your personal information. As such, we may rely on the following legal bases to process your personal information:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Consent.  We may process your information if you have given us permission (i.e. , consent) to use your personal information for a specific purpose. You can withdraw your consent at any time. Learn more about  withdrawing your consent .` }} />
      <p dangerouslySetInnerHTML={{ __html: `Performance of a Contract. We may process your personal information when we believe it is necessary to fulfill our contractual obligations to you, including providing our Services or at your request prior to entering into a contract with you.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Legitimate Interests. We may process your information when we believe it is reasonably necessary to achieve our legitimate business interests and those interests do not outweigh your interests and fundamental rights and freedoms. For example, we may process your personal information for some of the purposes described in order to:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Diagnose problems and/or prevent fraudulent activities` }} />
      <p dangerouslySetInnerHTML={{ __html: `Legal Obligations. We may process your information where we believe it is necessary for compliance with our legal obligations, such as to cooperate with a law enforcement body or regulatory agency, exercise or defend our legal rights, or disclose your information as evidence in litigation in which we are involved.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Vital Interests. We may process your information where we believe it is necessary to protect your vital interests or the vital interests of a third party, such as situations involving potential threats to the safety of any person.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you are located in Canada, this section applies to you.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may process your information if you have given us specific permission (i.e. , express consent) to use your personal information for a specific purpose, or in situations where your permission can be inferred (i.e. , implied consent). You can  withdraw your consent  at any time.` }} />
      <p dangerouslySetInnerHTML={{ __html: `In some exceptional cases, we may be legally permitted under applicable law to process your information without your consent, including, for example:` }} />
      <p dangerouslySetInnerHTML={{ __html: `If collection is clearly in the interests of an individual and consent cannot be obtained in a timely way` }} />
      <p dangerouslySetInnerHTML={{ __html: `For investigations and fraud detection and prevention` }} />
      <p dangerouslySetInnerHTML={{ __html: `For business transactions provided certain conditions are met` }} />
      <p dangerouslySetInnerHTML={{ __html: `If it is contained in a witness statement and the collection is necessary to assess, process, or settle an insurance claim` }} />
      <p dangerouslySetInnerHTML={{ __html: `For identifying injured, ill, or deceased persons and communicating with next of kin` }} />
      <p dangerouslySetInnerHTML={{ __html: `If we have reasonable grounds to believe an individual has been, is, or may be victim of financial abuse` }} />
      <p dangerouslySetInnerHTML={{ __html: `If it is reasonable to expect collection and use with consent would compromise the availability or the accuracy of the information and the collection is reasonable for purposes related to investigating a breach of an agreement or a contravention of the laws of Canada or a province` }} />
      <p dangerouslySetInnerHTML={{ __html: `If disclosure is required to comply with a subpoena, warrant, court order, or rules of the court relating to the production of records` }} />
      <p dangerouslySetInnerHTML={{ __html: `If it was produced by an individual in the course of their employment, business, or profession and the collection is consistent with the purposes for which the information was produced` }} />
      <p dangerouslySetInnerHTML={{ __html: `If the collection is solely for journalistic, artistic, or literary purposes` }} />
      <p dangerouslySetInnerHTML={{ __html: `If the information is publicly available and is specified by the regulations` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may disclose de-identified information for approved research or statistics projects, subject to ethics oversight and confidentiality commitments` }} />
      <h2>4. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We may share information in specific situations described in this section and/or with the following categories of third parties.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Vendors, Consultants, and Other Third-Party Service Providers. We may share your data with third-party vendors, service providers, contractors, or agents ( " third parties " ) who perform services for us or on our behalf and require access to such information to do that work. We have contracts in place with our third parties, which are designed to help safeguard your personal information. This means that they cannot do anything with your personal information unless we have instructed them to do it. They will also not share your personal information with any organization apart from us. They also commit to pr otect the data they hold on our behalf and to retain it for the period we instruct.` }} />
      <p dangerouslySetInnerHTML={{ __html: `The categories of third parties we may share personal information with are as follows:` }} />
      <p dangerouslySetInnerHTML={{ __html: `AI Platforms` }} />
      <p dangerouslySetInnerHTML={{ __html: `Cloud Computing Services` }} />
      <p dangerouslySetInnerHTML={{ __html: `Data Storage Service Providers` }} />
      <p dangerouslySetInnerHTML={{ __html: `Payment Processors` }} />
      <p dangerouslySetInnerHTML={{ __html: `User Account Registration &amp; Authentication Services` }} />
      <p dangerouslySetInnerHTML={{ __html: `Performance Monitoring Tools` }} />
      <p dangerouslySetInnerHTML={{ __html: `We also may need to share your personal information in the following situations:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Business Transfers. We may share or transfer your information in connection with, or during negotiations of, any merger, sale of company assets, financing, or acquisition of all or a portion of our business to another company.` }} />
      <h2>5. DO WE OFFER ARTIFICIAL INTELLIGENCE-BASED PRODUCTS?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We offer products, features, or tools powered by artificial intelligence, machine learning, or similar technologies.` }} />
      <p dangerouslySetInnerHTML={{ __html: `As part of our Services, we offer products, features, or tools powered by artificial intelligence, machine learning, or similar technologies (collectively, " AI Products " ). These tools are designed to enhance your experience and provide you with innovative solutions. The terms in this Privacy Notice govern your use of the AI Products within our Services.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Our AI Products` }} />
      <p dangerouslySetInnerHTML={{ __html: `Our AI Products are designed for the following functions:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Text analysis - extracting structured data from invoice text` }} />
      <p dangerouslySetInnerHTML={{ __html: `AI automation - automatically categorizing and organizing financial documents` }} />
      <p dangerouslySetInnerHTML={{ __html: `What Data is Sent to AI Services` }} />
      <p dangerouslySetInnerHTML={{ __html: `We send ONLY extracted OCR text from your invoices to our AI provider for analysis. Specifically:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `Text extracted from invoices (vendor names, amounts, dates, descriptions)` }} />
        <li dangerouslySetInnerHTML={{ __html: `NO images or PDF files are ever sent to AI services` }} />
        <li dangerouslySetInnerHTML={{ __html: `NO device identifiers or personal information beyond the invoice text` }} />
        <li dangerouslySetInnerHTML={{ __html: `We send only the minimum text required for analysis` }} />
        <li dangerouslySetInnerHTML={{ __html: `We do not use your invoice data for advertising or marketing purposes` }} />
        <li dangerouslySetInnerHTML={{ __html: `We configure AI providers to minimize data retention where technically available` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `The AI analysis happens in the cloud (when enabled) but follows a strict privacy-first model. We use business-tier API access with enterprise data processing agreements where available to limit data retention by AI providers.` }} />
      <h2>IMAGE PROCESSING AND PRIVACY</h2>
      <p dangerouslySetInnerHTML={{ __html: `DuEasy processes invoice images and PDFs entirely on your device. We do not upload or transmit your document images or PDFs to our servers or third-party services.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Here's how it works:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `Images/PDFs are processed locally on your device using on-device OCR (Optical Character Recognition)` }} />
        <li dangerouslySetInnerHTML={{ __html: `Only the extracted text data from your invoices is sent to our cloud service for analysis` }} />
        <li dangerouslySetInnerHTML={{ __html: `Your original images and PDFs remain on your device and are never transmitted` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `This local-first approach ensures your sensitive financial documents stay private and secure on your device.` }} />
      <h2>ICLOUD SYNC AND BACKUP</h2>
      <p dangerouslySetInnerHTML={{ __html: `DuEasy offers optional iCloud synchronization and backup features to keep your data in sync across your Apple devices.` }} />
      <p dangerouslySetInnerHTML={{ __html: `How iCloud Sync Works:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `All data is stored in YOUR private iCloud account using Apple's CloudKit service` }} />
        <li dangerouslySetInnerHTML={{ __html: `Your document data (extracted information, due dates, reminders) syncs between your devices signed in with the same Apple ID` }} />
        <li dangerouslySetInnerHTML={{ __html: `We do not have access to your iCloud data - it is stored in your private iCloud container` }} />
        <li dangerouslySetInnerHTML={{ __html: `Apple manages the storage, encryption, and synchronization` }} />
        <li dangerouslySetInnerHTML={{ __html: `You can disable iCloud sync at any time in the app settings` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `iCloud Backup:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `If enabled, encrypted backups of your document data are stored in your iCloud Drive` }} />
        <li dangerouslySetInnerHTML={{ __html: `Backups are encrypted with AES-256-GCM encryption before being uploaded` }} />
        <li dangerouslySetInnerHTML={{ __html: `We cannot access or decrypt your iCloud backups` }} />
        <li dangerouslySetInnerHTML={{ __html: `You control backup retention and can delete backups at any time` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `Important Notes:` }} />
      <ul>
        <li dangerouslySetInnerHTML={{ __html: `iCloud sync is optional - you can use DuEasy entirely on-device without iCloud` }} />
        <li dangerouslySetInnerHTML={{ __html: `Apple is the data processor for iCloud storage, not DuEasy` }} />
        <li dangerouslySetInnerHTML={{ __html: `Your data in iCloud is subject to Apple's Privacy Policy: <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener noreferrer">https://www.apple.com/legal/privacy/</a>` }} />
        <li dangerouslySetInnerHTML={{ __html: `iCloud storage uses your iCloud storage quota` }} />
        <li dangerouslySetInnerHTML={{ __html: `Syncing requires an active internet connection` }} />
      </ul>
      <p dangerouslySetInnerHTML={{ __html: `To learn more about how Apple handles your iCloud data, visit Apple's privacy policy.` }} />
      <h2>6. IS YOUR INFORMATION TRANSFERRED INTERNATIONALLY?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We may transfer, store, and process your information in countries other than your own.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Our servers are located in the United States . Regardless of your location,  please be aware that your information may be transferred to, stored by, and processed by us in our facilities and in the facilities of the third parties with whom we may share your personal information (see " WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION? " above), including facilities in the United States,  and other countries.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you are a resident in the European Economic Area (EEA), United Kingdom (UK), or Switzerland, then these countries may not necessarily have data protection laws or other similar laws as comprehensive as those in your country. However, we will take all necessary measures to protect your personal information in accordance with this Privacy Notice and applicable law.` }} />
      <p dangerouslySetInnerHTML={{ __html: `European Commission's Standard Contractual Clauses:` }} />
      <p dangerouslySetInnerHTML={{ __html: `We have implemented measures to protect your personal information, including by using the European Commission's Standard Contractual Clauses for transfers of personal information between our group companies and between us and our third-party providers. These clauses require all recipients to protect all personal information that they process originating from the EEA or UK in accordance with European data protection laws and regulations.   Our Standard Contractual Clauses can be provided upon request.   We have implemented similar appropriate safeguards with our third-party service providers and partners and further details can be provided upon request.` }} />
      <h2>7. HOW LONG DO WE KEEP YOUR INFORMATION?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We keep your information for as long as necessary to fulfill the purposes outlined in this Privacy Notice unless otherwise required by law.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We will only keep your personal information for as long as it is necessary for the purposes set out in this Privacy Notice, unless a longer retention period is required or permitted by law (such as tax, accounting, or other legal requirements). No purpose in this notice will require us keeping your personal information for as long as you have an account with us .` }} />
      <p dangerouslySetInnerHTML={{ __html: `When we have no ongoing legitimate business need to process your personal information, we will either delete or anonymize such information, or, if this is not possible (for example, because your personal information has been stored in backup archives), then we will securely store your personal information and isolate it from any further processing until deletion is possible.` }} />
      <h2>8. HOW DO WE KEEP YOUR INFORMATION SAFE?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We aim to protect your personal information through a system of organizational and technical security measures.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We have implemented appropriate and reasonable technical and organizational security measures designed to protect the security of any personal information we process. However, despite our safeguards and efforts to secure your information, no electronic transmission over the Internet or information storage technology can be guaranteed to be 100% secure, so we cannot promise or guarantee that hackers, cybercriminals, or other unauthorized third parties will not be able to defeat our security and improperly collect, access, steal, or modify your information. Although we will do our best to protect your personal information, transmission of personal information to and from our Services is at your own risk. You should only access the Services within a secure environment.` }} />
      <h2>9. DO WE COLLECT INFORMATION FROM MINORS?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  We do not knowingly collect data from or market to children under 18 years of age or the equivalent age as specified by law in your jurisdiction .` }} />
      <p dangerouslySetInnerHTML={{ __html: `We do not knowingly collect, solicit data from, or market to children under 18 years of age or the equivalent age as specified by law in your jurisdiction , nor do we knowingly sell such personal information. By using the Services, you represent that you are at least 18 or the equivalent age as specified by law in your jurisdiction or that you are the parent or guardian of such a minor and consent to such minor dependent’s use of the Services. If we learn that personal information from users less than 18 years of age or the equivalent age as specified by law in your jurisdiction has been collected, we will deactivate the account and take reasonable measures to promptly delete such data from our records. If you become aware of any data we may have collected from children under age 18 or the equivalent age as specified by law in your jurisdiction , please contact us at dueasy.sup@gmail.com .` }} />
      <h2>10. WHAT ARE YOUR PRIVACY RIGHTS?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:   Depending on your state of residence in the US or in some regions, such as the European Economic Area (EEA), United Kingdom (UK), Switzerland, and Canada , you have rights that allow you greater access to and control over your personal information.   You may review, change, or terminate your account at any time, depending on your country, province, or state of residence.` }} />
      <p dangerouslySetInnerHTML={{ __html: `In some regions (like the EEA, UK, Switzerland, and Canada ), you have certain rights under applicable data protection laws. These may include the right (i) to request access and obtain a copy of your personal information, (ii) to request rectification or erasure; (iii) to restrict the processing of your personal information; (iv) if applicable, to data portability; and (v) not to be subject to automated decision-making. If a decision that produces legal or similarly significant effects is made solely by automated means, we will inform you, explain the main factors, and offer a simple way to request human review. In certain circumstances, you may also have the right to object to the processing of your personal information. You can make such a request by contacting us by using the contact details provided in the section " HOW CAN YOU CONTACT US ABOUT THIS NOTICE? " below.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We will consider and act upon any request in accordance with applicable data protection laws.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you are located in the EEA or UK and you believe we are unlawfully processing your personal information, you also have the right to complain to your Member State data protection authority or  UK data protection authority .` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you are located in Switzerland, you may contact the Federal Data Protection and Information Commissioner .` }} />
      <p dangerouslySetInnerHTML={{ __html: `Withdrawing your consent: If we are relying on your consent to process your personal information, which may be express and/or implied consent depending on the applicable law, you have the right to withdraw your consent at any time. You can withdraw your consent at any time by contacting us by using the contact details provided in the section " HOW CAN YOU CONTACT US ABOUT THIS NOTICE? " below .` }} />
      <p dangerouslySetInnerHTML={{ __html: `However, please note that this will not affect the lawfulness of the processing before its withdrawal nor, when applicable law allows, will it affect the processing of your personal information conducted in reliance on lawful processing grounds other than consent.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Account Information` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you would at any time like to review or change the information in your account or terminate your account, you can:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Contact us using the contact information provided.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Upon your request to terminate your account, we will deactivate or delete your account and information from our active databases. However, we may retain some information in our files to prevent fraud, troubleshoot problems, assist with any investigations, enforce our legal terms and/or comply with applicable legal requirements.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you have questions or comments about your privacy rights, you may email us at dueasy.sup@gmail.com .` }} />
      <h2>11. CONTROLS FOR DO-NOT-TRACK FEATURES</h2>
      <p dangerouslySetInnerHTML={{ __html: `Most web browsers and some mobile operating systems and mobile applications include a Do-Not-Track ( "DNT" ) feature or setting you can activate to signal your privacy preference not to have data about your online browsing activities monitored and collected. At this stage, no uniform technology standard for recognizing and implementing DNT signals has been finalized . As such, we do not currently respond to DNT browser signals or any other mechanism that automatically communicates your choice not to be tracked online. If a standard for online tracking is adopted that we must follow in the future, we will inform you about that practice in a revised version of this Privacy Notice.` }} />
      <p dangerouslySetInnerHTML={{ __html: `California law requires us to let you know how we respond to web browser DNT signals. Because there currently is not an industry or legal standard for recognizing or honoring DNT signals, we do not respond to them at this time.` }} />
      <h2>12. DO UNITED STATES RESIDENTS HAVE SPECIFIC PRIVACY RIGHTS?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  If you are a resident of California, Colorado, Connecticut, Delaware, Florida, Indiana, Iowa, Kentucky, Maryland, Minnesota, Montana, Nebraska, New Hampshire, New Jersey, Oregon, Rhode Island, Tennessee, Texas, Utah, or Virginia , you may have the right to request access to and receive details about the personal information we maintain about you and how we have processed it, correct inaccuracies, get a copy of, or delete your personal information. You may also have the right to withdraw your consent to our processing of your personal information. These rights may be limited in some circumstances by applicable law. More information is provided below.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Categories of Personal Information We Collect` }} />
      <p dangerouslySetInnerHTML={{ __html: `The table below shows the categories of personal information we have collected in the past twelve (12) months. The table includes illustrative examples of each category and does not reflect the personal information we collect from you. For a comprehensive inventory of all personal information we process, please refer to the section " WHAT INFORMATION DO WE COLLECT? "` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category Examples Collected` }} />
      <p dangerouslySetInnerHTML={{ __html: `A. Identifiers` }} />
      <p dangerouslySetInnerHTML={{ __html: `Contact details, such as real name, alias, postal address, telephone or mobile contact number, unique personal identifier, online identifier, Internet Protocol address, email address, and account name` }} />
      <p dangerouslySetInnerHTML={{ __html: `YES (Apple user ID required; email address optional and may be Apple relay - we do not collect IP addresses, postal addresses, or phone numbers)` }} />
      <p dangerouslySetInnerHTML={{ __html: `B. Personal information as defined in the California Customer Records statute` }} />
      <p dangerouslySetInnerHTML={{ __html: `Name, contact information, education, employment, employment history, and financial information` }} />
      <p dangerouslySetInnerHTML={{ __html: `YES (email and financial data from scanned invoices only - we do not collect education, employment, or postal addresses)` }} />
      <p dangerouslySetInnerHTML={{ __html: `C . Protected classification characteristics under state or federal law` }} />
      <p dangerouslySetInnerHTML={{ __html: `Gender, age, date of birth, race and ethnicity, national origin, marital status, and other demographic data` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `D . Commercial information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Transaction information, purchase history, financial details, and payment information` }} />
      <h2>YES</h2>
      <p dangerouslySetInnerHTML={{ __html: `E . Biometric information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Fingerprints and voiceprints` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `F . Internet or other similar network activity` }} />
      <p dangerouslySetInnerHTML={{ __html: `Browsing history, search history, online behavior , interest data, and interactions with our and other websites, applications, systems, and advertisements` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `G . Geolocation data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Device location` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `H. Audio, electronic, sensory, or similar information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Images and audio, video or call recordings created in connection with our business activities` }} />
      <p dangerouslySetInnerHTML={{ __html: `YES (images stored locally on device only - not transmitted to servers)` }} />
      <p dangerouslySetInnerHTML={{ __html: `I . Professional or employment-related information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Business contact details in order to provide you our Services at a business level or job title, work history, and professional qualifications if you apply for a job with us` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `J . Education Information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Student records and directory information` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `K . Inferences drawn from collected personal information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Inferences drawn from any of the collected personal information listed above to create a profile or summary about, for example, an individual’s preferences and characteristics` }} />
      <h2>NO</h2>
      <p dangerouslySetInnerHTML={{ __html: `L . Sensitive personal Information Account login information and financial information including account access details` }} />
      <h2>YES</h2>
      <p dangerouslySetInnerHTML={{ __html: `We only collect sensitive personal information, as defined by applicable privacy laws or the purposes allowed by law or with your consent. Sensitive personal information may be used, or disclosed to a service provider or contractor, for additional, specified purposes. You may have the right to limit the use or disclosure of your sensitive personal information. We do not collect or process sensitive personal information for the purpose of inferring characteristics about you.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may also collect other personal information outside of these categories through instances where you interact with us in person, online, or by phone or mail in the context of:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Receiving help through our customer support channels;` }} />
      <p dangerouslySetInnerHTML={{ __html: `Participation in customer surveys or contests; and` }} />
      <p dangerouslySetInnerHTML={{ __html: `Facilitation in the delivery of our Services and to respond to your inquiries.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We will use and retain the collected personal information as needed to provide the Services or for:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category A - As long as the user has an account with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category B - As long as the user has an account with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category D - As long as the user has an account with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category H - As long as the user has an account with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category L - As long as the user has an account with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Sources of Personal Information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Learn more about the sources of personal information we collect in " WHAT INFORMATION DO WE COLLECT? "` }} />
      <p dangerouslySetInnerHTML={{ __html: `How We Use and Share Personal Information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Learn more about how we use your personal information in the section, " HOW DO WE PROCESS YOUR INFORMATION? "` }} />
      <p dangerouslySetInnerHTML={{ __html: `Will your information be shared with anyone else?` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may disclose your personal information with our service providers pursuant to a written contract between us and each service provider. Learn more about how we disclose personal information to in the section, " WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION? "` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may use your personal information for our own business purposes, such as for undertaking internal research for technological development and demonstration. This is not considered to be "selling" of your personal information.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We have not sold or shared any personal information to third parties for a business or commercial purpose in the preceding twelve (12) months.  We have disclosed the following categories of personal information to third parties for a business or commercial purpose in the preceding twelve (12) months:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category A. Identifiers` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category B. Personal information as defined in the California Customer Records law` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category D . Commercial information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category H . Audio, electronic, visual, and similar information` }} />
      <p dangerouslySetInnerHTML={{ __html: `Category L . Sensitive personal information` }} />
      <p dangerouslySetInnerHTML={{ __html: `The categories of third parties to whom we disclosed personal information for a business or commercial purpose can be found under " WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION? "` }} />
      <p dangerouslySetInnerHTML={{ __html: `Your Rights` }} />
      <p dangerouslySetInnerHTML={{ __html: `You have rights under certain US state data protection laws. However, these rights are not absolute, and in certain cases, we may decline your request as permitted by law. These rights include:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to know whether or not we are processing your personal data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to access  your personal data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to correct  inaccuracies in your personal data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to request the deletion of your personal data` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to obtain a copy  of the personal data you previously shared with us` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to non-discrimination for exercising your rights` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to opt out of the processing of your personal data if it is used for targeted advertising (or sharing as defined under California’s privacy law) , the sale of personal data, or profiling in furtherance of decisions that produce legal or similarly significant effects ( "profiling" )` }} />
      <p dangerouslySetInnerHTML={{ __html: `Depending upon the state where you live, you may also have the following rights:` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to access the categories of personal data being processed (as permitted by applicable law, including the privacy law in Minnesota)` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to obtain a list of the categories of third parties to which we have disclosed personal data (as permitted by applicable law, including the privacy law in California, Delaware, and Maryland )` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to obtain a list of specific third parties to which we have disclosed personal data (as permitted by applicable law, including the privacy law in Minnesota and Oregon )` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to obtain a list of third parties to which we have sold personal data (as permitted by applicable law, including the privacy law in Connecticut)` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to review, understand, question, and depending on where you live, correct how personal data has been profiled (as permitted by applicable law, including the privacy law in Connecticut and Minnesota )` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to limit use and disclosure of sensitive personal data (as permitted by applicable law, including the privacy law in California)` }} />
      <p dangerouslySetInnerHTML={{ __html: `Right to opt out of the collection of sensitive data and personal data collected through the operation of a voice or facial recognition feature (as permitted by applicable law, including the privacy law in Florida)` }} />
      <p dangerouslySetInnerHTML={{ __html: `How to Exercise Your Rights` }} />
      <p dangerouslySetInnerHTML={{ __html: `To exercise these rights, you can contact us by visiting email: dueasy.sup@gmail.com , by emailing us at dueasy.sup@gmail.com , Support request through App Store Connect , or by referring to the contact details at the bottom of this document.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Under certain US state data protection laws, you can designate an authorized agent to make a request on your behalf. We may deny a request from an authorized agent that does not submit proof that they have been validly authorized to act on your behalf in accordance with applicable laws.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Request Verification` }} />
      <p dangerouslySetInnerHTML={{ __html: `Upon receiving your request, we will need to verify your identity to determine you are the same person about whom we have the information in our system. We will only use personal information provided in your request to verify your identity or authority to make the request. However, if we cannot verify your identity from the information already maintained by us, we may request that you provide additional information for the purposes of verifying your identity and for security or fraud-prevention purposes.` }} />
      <p dangerouslySetInnerHTML={{ __html: `If you submit the request through an authorized agent, we may need to collect additional information to verify your identity before processing your request and the agent will need to provide a written and signed permission from you to submit such request on your behalf.` }} />
      <p dangerouslySetInnerHTML={{ __html: `Appeals` }} />
      <p dangerouslySetInnerHTML={{ __html: `Under certain US state data protection laws, if we decline to take action regarding your request, you may appeal our decision by emailing us at dueasy.sup@gmail.com . We will inform you in writing of any action taken or not taken in response to the appeal, including a written explanation of the reasons for the decisions. If your appeal is denied, you may submit a complaint to your state attorney general.` }} />
      <p dangerouslySetInnerHTML={{ __html: `California "Shine The Light" Law` }} />
      <p dangerouslySetInnerHTML={{ __html: `California Civil Code Section 1798.83, also known as the "Shine The Light" law, permits our users who are California residents to request and obtain from us, once a year and free of charge, information about categories of personal information (if any) we disclosed to third parties for direct marketing purposes and the names and addresses of all third parties with which we shared personal information in the immediately preceding calendar year. If you are a California resident and would like to make such a request, please submit your request in writing to us by using the contact details provided in the section " HOW CAN YOU CONTACT US ABOUT THIS NOTICE? "` }} />
      <h2>13. DO WE MAKE UPDATES TO THIS NOTICE?</h2>
      <p dangerouslySetInnerHTML={{ __html: `In Short:  Yes, we will update this notice as necessary to stay compliant with relevant laws.` }} />
      <p dangerouslySetInnerHTML={{ __html: `We may update this Privacy Notice from time to time. The updated version will be indicated by an updated "Revised" date at the top of this Privacy Notice. If we make material changes to this Privacy Notice, we may notify you either by prominently posting a notice of such changes or by directly sending you a notification. We encourage you to review this Privacy Notice frequently to be informed of how we are protecting your information.` }} />
      <h2>14. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?</h2>
      <p dangerouslySetInnerHTML={{ __html: `If you have questions or comments about this notice, you may email us at dueasy.sup@gmail.com` }} />
      <h2>15. HOW CAN YOU REVIEW, UPDATE, OR DELETE THE DATA WE COLLECT FROM YOU?</h2>
      <p dangerouslySetInnerHTML={{ __html: `Based on the applicable laws of your country or state of residence in the US , you may have the right to request access to the personal information we collect from you, details about how we have processed it, correct inaccuracies, or delete your personal information. You may also have the right to withdraw your consent to our processing of your personal information. These rights may be limited in some circumstances by applicable law. To request to review, update, or delete your personal information, please visit: email: dueasy.sup@gmail.com .` }} />
      <p dangerouslySetInnerHTML={{ __html: `This Privacy Policy was created using Termly's Privacy Policy Generator` }} />
    </div>
  )
}
