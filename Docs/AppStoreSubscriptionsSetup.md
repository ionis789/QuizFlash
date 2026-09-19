# App Store subscriptions setup

This checklist records the external configuration required by the QuizFlash 1.0 subscription release. Never place credentials, API secrets, receipts, tax data, or banking details in this repository.

## Fixed identifiers

- Bundle ID: `com.sion.QuizFlash`
- Subscription group: `QuizFlash Premium`
- Monthly product: `com.sion.QuizFlash.premium.monthly`
- RevenueCat entitlement: `premium`
- RevenueCat offering: `default`
- RevenueCat App User ID: authenticated Firebase UID

## Apple Developer and App Store Connect

- [ ] Confirm the distribution team owns `com.sion.QuizFlash`.
- [ ] Enable In-App Purchase and Sign in with Apple for the App ID.
- [ ] Confirm Release signing uses the distribution team.
- [ ] Accept the Paid Apps Agreement and complete tax and banking details.
- [ ] Create the `QuizFlash Premium` subscription group.
- [ ] Create the monthly product with the identifier above.
- [ ] Add English, Romanian, and Russian names and descriptions.
- [ ] Configure availability and review screenshots.
- [ ] Leave Billing Grace Period disabled for version 1.0.
- [ ] Create a Sandbox tester and record its account outside the repository.

## RevenueCat

- [ ] Create the QuizFlash project and iOS app.
- [ ] Connect the Apple credentials required for product import and receipt verification.
- [x] Import the monthly App Store product.
- [x] Create the `premium` entitlement and attach the Test Store and App Store monthly products.
- [x] Create the `default` offering with the `$rc_monthly` package.
- [ ] Configure restore behavior to transfer purchases to the latest App User ID.
- [ ] Obtain the public iOS SDK key for app configuration.
- [ ] Create a server secret for RevenueCat API reconciliation.
- [ ] Create a webhook authorization secret.
- [ ] Store both server secrets only in Cloudflare Worker secrets.

## Server configuration

- [ ] Add the RevenueCat server API key as a Cloudflare Worker secret.
- [ ] Add the RevenueCat webhook authorization secret as a Cloudflare Worker secret.
- [ ] Configure the RevenueCat webhook URL as `/v1/billing/webhook` on the production Worker.
- [ ] Declare the Firebase UIDs allowed to receive Sandbox entitlements in server configuration.
- [ ] Include the Apple reviewer account UID only after the review account exists.

## Commercial and review data

- [x] Set the monthly price to the 5.99 USD reference tier with Apple's regional equivalents.
- [ ] Choose distribution countries.
- [ ] Provide the public business identity and support contact.
- [ ] Publish privacy, terms, and support pages.
- [ ] Complete App Privacy, age rating, DSA, export, and SDK declarations.
- [ ] Prepare real localized screenshots and reviewer instructions.
- [ ] Submit version 1.0 and both subscriptions together.
- [ ] Select manual release after approval.

## Verification record

Record dates and outcomes here without account data or secrets.

| Check | Date | Result |
| --- | --- | --- |
| Products load in Sandbox |  |  |
| Monthly purchase activates server entitlement |  |  |
| Restore on another device succeeds |  |  |
| Transfer removes the previous account entitlement |  |  |
| Expiration or revocation removes access |  |  |
| TestFlight purchase flow succeeds |  |  |
