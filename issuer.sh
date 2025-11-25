#!/usr/bin/env bash

set -e # break on error
set -u # warn against undefined variables
set -o pipefail
# set -x # echo statements before executing

# When calling this script, set $WALLET_REACHABLE_ADDRESS to a domain or IP address that the wallet can reach.
export WALLET_REACHABLE_ADDRESS=${WALLET_REACHABLE_ADDRESS:-127.0.0.1}

# Determine the directory of this script
DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd -P)"

function setup_issuer() {
    echo "Running setup tasks..."

    # Fetch the NL Wallet at its `main` branch
    if [[ ! -d "$DIR/nl-wallet" ]]; then
        echo "NL Wallet checkout not found; cloning repository"
        git clone https://github.com/MinBZK/nl-wallet "$DIR/nl-wallet"
    else
        git -C "$DIR/nl-wallet" fetch origin
    fi
    git -C "$DIR/nl-wallet" switch --detach a9aa33ccaa024263bacd8fdb81fec4b80dfcb2e1

    # Load utility bash functions from nl-wallet
    source "$DIR/nl-wallet/scripts/utils.sh"

    # Create some directories that we write into
    mkdir -p "$DIR/issuer/resources/status-lists" "$DIR/certs/demo_issuer" "$DIR/certs/demo_relying_party" "$DIR/certs/tls"

    # Compile nl-wallet servers
    cargo build --manifest-path "$DIR/nl-wallet/wallet_core/Cargo.toml" \
         --package demo_issuer \
         --bin demo_issuer
    cargo build --manifest-path "$DIR/nl-wallet/wallet_core/Cargo.toml" \
        --package issuance_server \
        --no-default-features \
        --features "allow_insecure_url,postgres" \
        --bin issuance_server
    cp "$DIR/nl-wallet/wallet_core/target/debug/demo_issuer" "$DIR/issuer"
    cp "$DIR/nl-wallet/wallet_core/target/debug/issuance_server" "$DIR/issuer"

    # Generate certificates and keys for the `issuance_server`
    export BASE_DIR="$DIR/nl-wallet"
    export TARGET_DIR="$DIR/certs"
    DEVENV="$DIR" generate_demo_issuer_key_pairs myissuer
    DEVENV="$DIR" generate_demo_relying_party_key_pair myissuer

    # Generate certificates and keys for the `demo_issuer`
    USE_SINGLE_CA=false generate_or_reuse_root_ca "$DIR/certs/tls" ca.example.com
    DEVENV="$DIR/nl-wallet/scripts/devenv" generate_ssl_key_pair_with_san "$DIR/certs/tls" demo_issuer "$DIR/certs/tls/ca.crt.pem" "$DIR/certs/tls/ca.key.pem"

    # generate `issuance_server` and `demo_issuer` config file
    BASE64="openssl base64 -e -A"
    export ISSUER_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.issuer.crt.pem" -inform pem -outform der | ${BASE64})
    export ISSUER_PID_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.issuer.pid.crt.pem" -inform pem -outform der | ${BASE64})
    export READER_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.reader.crt.pem" -inform pem -outform der | ${BASE64})
    export KEY_ISSUER=$(cat "$DIR/certs/demo_issuer/myissuer.issuer.key.der" | ${BASE64})
    export CRT_ISSUER=$(cat "$DIR/certs/demo_issuer/myissuer.issuer.crt.der" | ${BASE64})
    export KEY_TSL=$(cat "$DIR/certs/demo_issuer/myissuer.tsl.key.der" | ${BASE64})
    export CRT_TSL=$(cat "$DIR/certs/demo_issuer/myissuer.tsl.crt.der" | ${BASE64})
    export KEY_READER=$(cat "$DIR/certs/demo_relying_party/myissuer.key.der" | ${BASE64})
    export CRT_READER=$(cat "$DIR/certs/demo_relying_party/myissuer.crt.der" | ${BASE64})
    export DEMO_ISSUER_CA_CRT=$(cat "$DIR/certs/tls/ca.crt.der" | ${BASE64})
    export DEMO_ISSUER_CRT=$(cat "$DIR/certs/tls/demo_issuer.crt.der" | ${BASE64})
    export DEMO_ISSUER_KEY=$(cat "$DIR/certs/tls/demo_issuer.key.der" | ${BASE64})
    envsubst < "$DIR/config/issuance_server.template.toml" > "$DIR/issuer/issuance_server.toml"
    envsubst < "$DIR/config/demo_issuer.template.json" > "$DIR/issuer/demo_issuer.json"

    cp "$DIR/com.example.mycard.json" "$DIR/issuer/"

    # (Re)start postgres for the issuance_server
    "$DIR/nl-wallet/scripts/start-devenv.sh" postgres
    sleep 1 # Give postgres some time to start

    # Run migrations
    export DATABASE_URL="postgres://postgres:postgres@localhost:5432/issuance_server"
    cargo run --manifest-path "$DIR/nl-wallet/wallet_core/Cargo.toml" \
        --package issuance_server_migrations --bin issuance_server_migrations -- fresh
}

function start_services() {
    echo "Starting services..."

    # (Re)start the `issuance_server` and `demo_issuer`
    killall issuance_server demo_issuer || true
    pushd "$DIR/issuer"
    RUST_LOG=debug ./issuance_server &
    RUST_LOG=debug ./demo_issuer &
    popd

    QR_REQUEST_URI=$(printf %s "http://$WALLET_REACHABLE_ADDRESS:3007/disclosure/mycard/request_uri?session_type=cross_device" | jq -sRr @uri)
    QR="https://app.demo.voorbeeldwallet.nl/deeplink/disclosure_based_issuance?request_uri=$QR_REQUEST_URI&request_uri_method=post&client_id=myissuer.example.com"

    # Ensure the QR ends up below the log lines of `issuance_server` and `demo_issuer`
    sleep 0.5

    npx qrcode --small "$QR"

    echo
    echo "QR code contents: $QR"
}

# Main logic based on parameter
MODE="${1:-all}"
case "$MODE" in
    setup)
        setup_issuer
        ;;
    start)
        start_services
        ;;
    stop)
        killall issuance_server demo_issuer || true
        ;;
    all)
        setup_issuer
        start_services
        ;;
    *)
        echo "Usage: $0 [{setup|start|stop}]"
        echo "  setup - Run setup tasks only"
        echo "  start - Start services only (requires setup to have been run)"
        echo "  stop  - Stop services"
        echo
        echo "If no parameter is provided, setup and start are run."
        exit 1
        ;;
esac
