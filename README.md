# OpenAuthenticator

A native macOS menu bar app for TOTP two-factor authentication. Import your accounts from Google Authenticator, 1Password, or paste `otpauth://` URIs directly.

## Install

Download the latest `.zip` from [Releases](https://github.com/xatuke/openauthenticator/releases), unzip, and move `OpenAuthenticator.app` to `/Applications`.

> Since this is signed with a development certificate (not notarized), you may need to right-click → Open on first launch, or allow it in System Settings → Privacy & Security.

## Build from source

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/xatuke/openauthenticator.git
cd openauthenticator
xcodegen generate
```

Build and sign (requires an Apple Development certificate — a free Apple ID works):

```sh
xcodebuild -project OpenAuthenticator.xcodeproj \
  -scheme OpenAuthenticator \
  -configuration Release \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  build
```

Or use the included script:

```sh
./build.sh        # Debug build
./build.sh Release  # Release build
```

The app bundle is output to Xcode's DerivedData. The build script prints the path.

## Usage

A shield icon appears in your menu bar. Click it to authenticate and view your codes.

### Importing accounts

#### Google Authenticator

1. On your phone, open **Google Authenticator** → **Transfer accounts** → **Export accounts**
2. Screenshot all QR code pages
3. Transfer the screenshots to your Mac
4. In OpenAuthenticator, click the import button or drag & drop the images

#### 1Password (CSV or 1PUX)

1. Export from 1Password as CSV or `.1pux`
2. Click the import button and select the file

#### Manual URI

Click the link icon in the header and paste an `otpauth://totp/...` URI directly.

## Security

- Secrets are stored in the macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `.userPresence` access control (requires biometric or passcode for every access)
- The app locks automatically after 60 seconds of inactivity
- Copied codes are auto-cleared from the clipboard after 10 seconds
- Clipboard entries are marked as concealed to prevent clipboard managers from recording them
- Secrets are zeroed in memory when the app locks

## License

MIT
