# NL Wallet Demo Terminal Issuer and Verifier

This repository contains bash scripts that set up a demo NL Wallet issuer or verifier on your local machine in your terminal.

- `issuer.sh`: Sets up a demo NL Wallet issuer that can issue a demo attestation to the NL Wallet demo app.
- `verifier.sh`: Sets up a demo NL Wallet verifier that can request and verify disclosed attributes from the NL Wallet demo app. Also performs a disclosure session with your NL Wallet in your terminal. You can read the script to see example code that you would need to implement in the backend of your webapp.

## Prerequisites

- Bash
- Rust and `cargo` (for building the servers)
- `openssl` (for certificate generation)
- Docker (for running PostgreSQL)
- NPM (for generating the QR code)
- `jq` (for JSON processing and URL encoding)
- The NL Wallet project source code (automatically cloned if not present)

## `issuer.sh` - Demo Issuer

The `issuer.sh` script sets up a demo issuer that can issue attestations to the NL Wallet. It effectively automates the steps documented in the [NL Wallet "Create an Issuer" guide](https://minbzk.github.io/nl-wallet/main/get-started/create-an-issuer.html).

### What It Does

The script sets up two services:
- `demo_issuer`: exposes a HTTP API that takes a BSN, and responds with a set of attributes to be issued.
- `issuance_server`: performs disclosure with the wallet in order to obtain the BSN, sends that to the `demo_issuer`, and then issues the attributes that `demo_issuer` responds with.

Specifically, the `issuer.sh` script performs the following tasks:

1. Clones the NL Wallet project (if not already present)
2. Compiles the `demo_issuer` and `issuance_server` servers
3. Generates cryptographic certificates and keys for these servers
4. Creates configuration files for these servers
5. Starts a PostgreSQL database and runs migrations
6. Starts both the `demo_issuer` and `issuance_server` servers
7. Shows a QR code in the terminal that the wallet can scan to begin the issuance flow

### Configuration

Before running the script, you should edit the three JSON configuration files in the root directory:

#### 1. `com.example.mycard.json`

Defines the attestation, in particular its `vct` (i.e., the attestation type), its contained attributes, and how it is rendered in the NL Wallet.

The `vct` should be unique, i.e., not be the same as the `vct` anyone else has chosen.
If you rename the `vct` to some value that you like, be sure to use it with global search & replace so that the configuration files are updated accordingly, and rerun `issuer.sh`.

For more information, see [the documentation](https://minbzk.github.io/nl-wallet/main/get-started/create-an-issuer.html#creating-a-technical-attestation-schema-document).

#### 2. `myissuer_issuer_auth.json`

Defines the organization information for the issuer that is displayed to the user in the NL Wallet app during issuance. Contains:

- Display name and legal name (in multiple languages)
- Description
- Website URL
- City
- Category (e.g., "Insurance")
- Logo (as SVG or image data)
- Country code
- KVK number (Dutch Chamber of Commerce registration number)
- Privacy policy URL

Edit this file to customize how your issuer appears in the wallet.

For more information, see [the documentation](https://minbzk.github.io/nl-wallet/main/get-started/create-an-issuer.html#creating-an-issuer-authentication-document).

#### 3. `myissuer_reader_auth.json`

Before issuing, the wallet discloses the BSN to the `issuance_server`.
This file contains the following data to facilitate that:

- Purpose statement (why the attributes are being disclosed)
- Retention policy (how long the attributes are being stored)
- Sharing policy (whether the attributes can be shared with other services)
- Deletion policy (whether the attributes can be deleted)
- Organization information (same as issuer_auth.json)
- Authorized attributes (which attributes are requested from the wallet)

For more information, see [the documentation](https://minbzk.github.io/nl-wallet/main/get-started/create-an-issuer.html#creating-a-reader-authentication-document).

#### 4. `config/demo_issuer.template.json`

This file defines which BSN results in which attributes.

### Running `issuer.sh`

```bash
WALLET_REACHABLE_ADDRESS=192.168.1.2 ./issuer.sh
```

Here, the `WALLET_REACHABLE_ADDRESS` must be an IP address or domain referring to your machine (or at least the machine that will run the servers) that is reachable by the wallet app.

The script supports the following modes:

```bash
./issuer.sh all     # Setup and start (default if no argument provided)
./issuer.sh setup   # Run setup tasks only
./issuer.sh start   # Start services only (requires setup to have been run)
./issuer.sh stop    # Stop services
```

### Result

After running the script successfully, the `issuer` subfolder will contain the servers and their configuration files.
Once they have been generated, you can run the servers directly from this folder if you like, as follows:

```sh
cd ./issuer
RUST_LOG=debug ./issuance_server &
RUST_LOG=debug ./demo_issuer &
```

However, whenever you edit one of the JSON files in the root of this repository, you will need to rerun `issuer.sh`.

The script will finish by printing a QR code in the terminal for the NL Wallet to scan.

### Next Steps

Once the script completes:

1. Open the NL Wallet application
2. Scan the generated QR code
3. Follow the issuance flow to receive the demo insurance attestation
4. The attestation will appear in your wallet with the information and styling you configured

## `verifier.sh` - Demo Verifier

The `verifier.sh` script sets up a demo verifier that can request and verify disclosed attributes from the NL Wallet.
It includes example (bash) code that shows what you would need to do in the backend of your app.

As such, it performs two tasks: it effectively automates the steps documented in the [NL Wallet "Create a Verifier" guide](https://minbzk.github.io/nl-wallet/main/get-started/create-a-verifier.html), and it includes demo code demonstrating how a session can be started and managed.

For a more complete demo, see the [demo relying party](nl-wallet/wallet_core/demo/demo_relying_party/src/app.rs) in the NL Wallet repositry.

### What It Does

The script sets up one service:
- `verification_server`: receives disclosure requests from your code, returns a session token, polls for wallet responses, and provides the disclosed attributes.

Specifically, the `verifier.sh` script performs the following tasks:

1. Clones the NL Wallet project (if not already present)
2. Compiles the `verification_server`
3. Generates cryptographic certificates and keys for the server
4. Creates configuration files for the server
5. Starts a PostgreSQL database and runs migrations
6. Starts the `verification_server`
7. Starts and runs a verification session with your NL Wallet

### Running `verifier.sh`

```bash
./verifier.sh all     # Setup, start, and run a session (default if no argument provided)
./verifier.sh setup   # Run setup tasks only
./verifier.sh start   # Start service only (requires setup to have been run)
./verifier.sh session # Start a verification session (requires service to be running)
./verifier.sh stop    # Stop service
```

### Starting a Verification Session

The `verifier.sh session` command (or `./verifier.sh all`) will:

1. POST to the verification_server to start a new session
2. Display a QR code for the wallet to scan
3. Wait for the wallet to respond with disclosed attributes
4. Print the disclosed attributes to stdout

## Troubleshooting

- Check that you have all [prerequisites](#prerequisites) installed
- If the script fails:
  - Check the error messages and ensure all configuration files are valid JSON
  - Enable the `set -x` line near the top of the script and rerun the script to see exactly the commands that it executes,
    and check that they contain no errors.
- If issuance/verification fails:
  - Check the debug output of the servers in your terminal
  - Check the logs of the NL Wallet app, as follows:
    - On iOS:
      1. Connect your iPhone to your Mac via USB cable
      2. Tap "Trust" on your iPhone to authorize the connection
      3. Open `Console.app` on your Mac
      4. Your iPhone should appear in the device list on the left sidebar
      5. Click on your iPhone to view its logs and search for `wallet_core`
    - On Android:
      1. Connect your Android phone to your machine via USB cable
      2. Enable USB debugging on your Android phone (in Developer Options settings)
      3. Tap "Allow" on your Android phone to authorize the connection
      4. Run `adb logcat | grep -i wallet_core` in your terminal to view the logs

## File Structure

```
.
├── issuer.sh                          # Issuer setup script
├── verifier.sh                        # Verifier setup script
├── LICENSE                            # License file
├── README.md                          # This file
├── config/                            # Config templates
│   ├── issuance_server.template.toml  # Configuration file template of the `issuance_server`
│   ├── demo_issuer.template.json      # Contains the attribute values that are issued
│   └── verification_server.template.toml # Configuration file template of the `verification_server`
├── myissuer_issuer_auth.json          # Issuer organization config
├── myissuer_reader_auth.json          # Data handling policies for issuer
├── myverifier_reader_auth.json        # Data handling policies for verifier
├── com.example.mycard.json            # Attestation template
├── nl-wallet/                         # NL Wallet source code (auto-cloned)
├── certs/                             # CA certs and keys, plus generated certs and keys
├── issuer/                            # Issuer output folder (created by issuer.sh)
│   ├── issuance_server                # Compiled binary
│   ├── demo_issuer                    # Compiled binary
│   ├── issuance_server.toml           # Generated config
│   ├── demo_issuer.json               # Generated config
│   ├── com.example.mycard.json        # Copied attestation template
│   └── resources/                     # Resources folder
├── verifier/                          # Verifier output folder (created by verifier.sh)
│   ├── verification_server            # Compiled binary
│   └── verification_server.toml       # Generated config
└── .gitignore                         # Git ignore file
```
