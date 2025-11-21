#!/usr/bin/env bash

set -e # break on error
set -u # warn against undefined variables
set -o pipefail
# set -x # echo statements before executing

# When calling this script, set $WALLET_REACHABLE_ADDRESS to a domain or IP address that the wallet can reach.
export WALLET_REACHABLE_ADDRESS=${WALLET_REACHABLE_ADDRESS:-127.0.0.1}

# Determine the directory of this script
DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd -P)"

function setup_verifier() {
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

    mkdir -p "$DIR/verifier"

    # Compile and setup nl-wallet verification_server
    cargo build --manifest-path "$DIR/nl-wallet/wallet_core/Cargo.toml" \
        --package verification_server \
        --no-default-features \
        --features "allow_insecure_url,postgres" \
        --bin verification_server
    cp "$DIR/nl-wallet/wallet_core/target/debug/verification_server" "$DIR/verifier/"

    # Generate private key and certificate for `verification_server`
    export BASE_DIR="$DIR/nl-wallet"
    export TARGET_DIR="$DIR/certs"
    export DEVENV="$DIR"
    generate_demo_relying_party_key_pair myverifier

    # generate verification_server config file
    local BASE64="openssl base64 -e -A"
    export ISSUER_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.issuer.crt.pem" -inform pem -outform der | ${BASE64})
    export ISSUER_PID_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.issuer.pid.crt.pem" -inform pem -outform der | ${BASE64})
    export READER_CA_CRT=$(openssl x509 -in "$DIR/certs/ca.reader.crt.pem" -inform pem -outform der | ${BASE64})
    export KEY_READER=$(cat "$DIR/certs/demo_relying_party/myverifier.key.der" | ${BASE64})
    export CRT_READER=$(cat "$DIR/certs/demo_relying_party/myverifier.crt.der" | ${BASE64})
    export EPHEMERAL_ID_SECRET=$(dd if=/dev/urandom bs="64" count=1 2>/dev/null | xxd -p | tr -d '\n')
    envsubst < "$DIR/config/verification_server.template.toml" > "$DIR/verifier/verification_server.toml"

    # Start postgres for the verification_server
    sh "$DIR/nl-wallet/scripts/start-devenv.sh" postgres
    sleep 1 # Give postgres some time to start

    # Run migrations
    export DATABASE_URL="postgres://postgres:postgres@localhost:5432/verification_server"
    cargo run --manifest-path "$DIR/nl-wallet/wallet_core/Cargo.toml" --package verification_server_migrations --bin verification_server_migrations -- fresh
}

function start_services() {
    echo "Starting services..."

    # (Re)start the verification_server
    killall verification_server || true
    pushd "$DIR/verifier"
    RUST_LOG=debug ./verification_server &
    popd
}

# Emulates an NL Wallet disclosure session in the terminal.
function do_session() {
    # Start the session. This happens when the user clicks on the <nl-wallet-button> button on your website.
    # `wallet_web` will POST the `usecase` associated to it to your backend.
    start_session "myusecase"

    # Print the QR code and wait for the session to complete, like `wallet_web` would do.
    emulate_frontend "$SESSION_RESPONSE"

    # Once wallet_web notices through its polling that the session has completed, it will run
    # the success closure that you passed to it when starting the session. In that closure
    # you can invoke your own backend, so that it can retrieve the disclosed attributes and
    # handle them as it sees fit.
    if [[ $? -eq 0 ]]; then
        fetch_attributes
    fi
}

# Starts the verification session by POSTing to the `verification_server`.
# Normally, this would be a POST HTTP handler that is invoked by `wallet_web`
# when the user clicks on the <nl-wallet-button> on your website.
# `wallet_web` passes the usecase as parameter.
function start_session {
    echo "Starting session..."

    local USECASE="$1"
    local REQUEST='{
        "usecase": "'$USECASE'",
        "dcql_query": {
            "credentials": [
                {
                    "id": "pid",
                    "format": "dc+sd-jwt",
                    "meta": {"vct_values": ["urn:eudi:pid:nl:1"]},
                    "claims": [{"path": ["bsn"]}]
                },
                {
                    "id": "mycard",
                    "format": "dc+sd-jwt",
                    "meta": {"vct_values": ["com.example.mycard"]},
                    "claims": [
                        {"path": ["product"]},
                        {"path": ["coverage"]},
                        {"path": ["start_date"]},
                        {"path": ["duration"]},
                        {"path": ["customer_number"]}
                    ]
                }
            ]
        },
        "return_url_template": "https://myapp.example.com/?wallet_session_token={session_token}"
    }'

    # Make the POST request to the verification_server to start the session
    local RESPONSE=$(curl -s -X POST "http://localhost:3010/disclosure/sessions" \
        -H "Content-Type: application/json" \
        -d "$REQUEST")

    echo "Session created, server responded with: "
    echo $RESPONSE | jq .

    # Extract the session token
    local SESSION_TOKEN=$(echo "$RESPONSE" | jq -r '.session_token')

    # Return the response that wallet_web expects
    SESSION_RESPONSE='{
        "status_url": "http://'$WALLET_REACHABLE_ADDRESS':3009/disclosure/sessions/'$SESSION_TOKEN'",
        "session_token": "'$SESSION_TOKEN'"
    }'
}

# This is normally done by `wallet_web` in your frontend. Prints the session QR code to the console.
# Polls until the status is DONE or something unexpected happens.
function emulate_frontend {
    echo "Polling status and showing QR..."

    local SESSION_RESPONSE="$1"
    local STATUS_URL=$(echo "$SESSION_RESPONSE" | jq -r '.status_url')

    while true; do
        local STATUS_RESPONSE=$(curl -s -X GET "$STATUS_URL?session_type=cross_device")
        local STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')

        case "$STATUS" in
            CREATED)
                npx qrcode --small $(echo "$STATUS_RESPONSE" | jq -r '.ul')
                ;;
            WAITING_FOR_RESPONSE)
                # Just continue polling
                ;;
            DONE)
                return 0
                ;;
            *)
                echo "Unexpected status: $STATUS"
                return 1
                ;;
        esac

        sleep 2
    done
}

# This would be an endpoint in your backend invoked by the success handler you passed to `wallet_web`.
# It fetches the disclosed attributes from the `verification_server` and can handle them as it sees fit.
function fetch_attributes {
    local SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.session_token')

    echo "Retrieving disclosed attributes..."
    local ATTRIBUTES=$(curl -s -X GET "http://127.0.0.1:3010/disclosure/sessions/$SESSION_TOKEN/disclosed_attributes")

    echo "Received attributes:"
    echo "$ATTRIBUTES" | jq .
}

# Main logic based on parameter
MODE="${1:-all}"
case "$MODE" in
    setup)
        setup_verifier
        ;;
    start)
        start_services
        ;;
    stop)
        killall verification_server || true
        ;;
    session)
        do_session
        ;;
    all)
        setup_verifier
        start_services
        sleep 1
        do_session
        ;;
    *)
        echo "Usage: $0 [{setup|start|stop|session}]"
        echo "  setup   - Run setup tasks only"
        echo "  start   - Start service only (requires setup to have been run)"
        echo "  stop    - Stop service"
        echo "  session - Start a verification session (requires service to be running)"
        echo
        echo "If no parameter is provided, setup and start are run."
        exit 1
        ;;
esac
