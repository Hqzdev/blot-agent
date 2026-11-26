# `CloudServiceTest.java`

Проверяет облачные сценарии с управляемыми часами и тестовыми зависимостями. Включает сессии, привязку и отзыв устройств, relay, снимки, аренду и учёт запросов модели.

[Исходник: `backend/cloud/src/test/java/dev/blot/cloud/CloudServiceTest.java`](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/backend/cloud/src/test/java/dev/blot/cloud/CloudServiceTest.java)

Модуль: [cloud](../../../../../../README.md). Раздел: [Проверки облака](index.md).

## Проверки

- `accountDeletionRequiresItsOwnCodeAndRemovesTheOwnerGraph`
- `browserAuthorizationRequiresPKCEAndBindsOneNativeClient`
- `webBrowserAuthorizationUsesTheConfiguredOriginAndExistingOwner`
- `emailVerificationRotatingSessionsAndDeviceProofAreRequired`
- `pairingRequiresOwnerConfirmationAndCannotReplaceCandidate`
- `relayIsDurableIdempotentSignedAndExpiresWithExplicitReplayFailure`
- `snapshotDonorMustBeCurrentSignedAndCompleteBeforePublication`
- `leasesFenceProcessesAndRequireUnknownActionReconciliation`
- `revocationAtomicallyRotatesEpochAndBlocksOldDeviceAndCiphertext`
- `quotaDoesNotDoubleChargeAndUnknownReservationsSurviveRestart`
- `encryptedBlobChunksKeepTheirManifestAndExpire`
- `resetDoesNotRevealExistenceThroughCooldownOrSmtpFailure`
- `modelInvocationIsClaimedOnceAndLogoutStopsQueuedCalls`
