# Data Models

Screenshot
- id
- createdAt
- imagePath
- thumbnailPath
- width
- height
- ocrText

Annotation
- id
- screenshotId
- type
- geometry
- style

UploadRecord
- id
- screenshotId
- provider
- url

StorageConfiguration (AppStorage & Keychain)
- defaultLocalDirectory
- selectedProvider
- customEndpointURL
- customAPIKey (Keychain)
- customAPISecret (Keychain)
- customAccessToken (Keychain)
- googleDriveAccessToken (Keychain)
- googleDriveRefreshToken (Keychain)
