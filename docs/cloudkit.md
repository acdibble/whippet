# CloudKit

Whippet uses the container `iCloud.codes.dibble.whippet`. Debug builds (Whippet Dev) use its Development
environment and releases use Production. The schema is edited in Development, usually by saving a record from Whippet
Dev, and deployed to Production in the [CloudKit Console](https://icloud.developer.apple.com).

## Private database: clipboard sync

Everything lives in the zone `Whippet`. Record names are `clip-`, `calc-` or `link-` followed by an HMAC under the
zone's key, so they reveal nothing.

| Record type | Fields | Notes |
|---|---|---|
| `Clip` | encrypted: `contentHash`, `kind`, `text`, `ocrText`, `copiedAt`, `updatedAt`, `timesCopied`, `pinnedAt`, `sourceBundleID`, `imageWidth`, `imageHeight`, `imageBytes`; asset: `image` | The image asset is encrypted with AES-GCM before upload. |
| `Calc` | encrypted: `expression`, `answer`, `mode`, `calculatedAt`, `updatedAt` | |
| `SyncKey` | encrypted: `secret` | One record, `sync-key`, holding the key for record names and images. |
| `Link` | encrypted: `uuid`, `name`, `keyword`, `template`, `appBundleID`, `createdAt`, `updatedAt` | Quicklinks, from 0.8.0. Record names are `link-` and an HMAC of the UUID. |
| `ClipboardItem`, `Calculation` | | Used before 0.3.0 and no longer read or written. Production can't delete them. |

The private database ignores security roles, but every type above must still have **no access for any role**, so
nobody can create records of these types in the public database.

## Public database: feedback

| Record type | Fields | Indexes |
|---|---|---|
| `Feedback` | `sealedKey` (Bytes), `sealed` (Bytes), `handled` (Int64); from 0.11.0 `attachments` (Asset List) and `attachmentCount` (Int64); before 0.6.0 also `message`, `email` and `details` (String) in plain text | `recordName` Queryable, `createdTimestamp` Sortable, `createdBy` Queryable |

From 0.6.0, the message, email and system details are sealed with HPKE to the public key in `WhippetFeedbackPublicKey`
(`project.yml`). Only the admin's private key, kept in iCloud Keychain and created in Settings › Developer, opens them.
From 0.11.0, each attached image is sealed the same way, separately, as one asset in `attachments`; `attachmentCount`
is plain so the admin pane knows to fetch them.
The roles below are still the first line of defence, and the only one for feedback sent by earlier versions.

| Record type | `_world` | `_icloud` | `_creator` | `Admin` |
|---|---|---|---|---|
| `Feedback` | none | Create | Read | Read, Write |
| `Clip`, `Calc`, `Link`, `SyncKey`, `ClipboardItem`, `Calculation`, `Users` | none | none | none | none |

CloudKit gives a new record type `_world` Read, `_icloud` Create and `_creator` Write by default, so every new type needs
its roles set by hand.

`Admin` is a custom role. Assign it to the admin's `Users` record in each environment separately, since role
assignments are data rather than schema.

## Before each deploy to Production

1. Compare every record type's security roles in Development with the table above, especially any type added since
   the last deploy.
2. Check that `Feedback` has the indexes above.
3. Deploy the schema to Production.
4. Check the roles in Production match too, then send feedback from a release build and confirm it arrives sealed.
