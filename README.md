# OpenAuthenticator

A native menu bar app for TOTP two-factor authentication. Import your accounts from Google Authenticator and access your codes with a single click.

## Install

Requires Swift 5.9+.

```sh
git clone https://github.com/xatuke/OpenAuthenticator.git
cd OpenAuthenticator
swift build -c release
```

The binary is at `.build/release/OpenAuthenticator`. Move it wherever you like:

```sh
cp .build/release/OpenAuthenticator /usr/local/bin/
```

## Usage

```sh
./OpenAuthenticator
```

A shield icon appears in your menu bar. Click it to open the app.

### Importing accounts

#### Google Authenticator

1. On your phone, open **Google Authenticator** > **Transfer accounts** > **Export accounts**
2. Screenshot all QR code pages (e.g. "QR code 1 of 3", "2 of 3", "3 of 3")
3. Transfer the screenshots to your computer
4. In OpenAuthenticator, click the QR icon or drag & drop all images onto the popover
5. Done — your codes appear immediately

The app also supports standard `otpauth://totp/...` QR codes from individual services.

## License

MIT
