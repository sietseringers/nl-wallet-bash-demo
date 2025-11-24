# Disclosure Session Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant user as User
    participant wallet_app as NL Wallet App
    participant rp_frontend as RP Frontend
    participant rp_backend as RP Backend
    participant vs as verification_server (OV)

    
    Note over user,vs: Session Initialization Phase
    user->>+rp_frontend: Click NL Wallet button
    rp_frontend->>+rp_backend: Request session initiation [wallet_web]
    rp_backend->>+vs: POST /disclosure/sessions<br/>(session_request)
    vs->>-rp_backend: Returns token_response<br/>(session_token)
    rp_backend->>-rp_frontend: Return QR/UL contents <br>(verification_server URL & session token)
    rp_frontend->>-user: Display QR code or UL
    loop Start polling loop
        rp_frontend->>+vs: Poll GET /disclosure/sessions/{session_token}
        vs->>-rp_frontend: session_status (CREATED or WAITING_FOR_RESPONSE or DONE)
    end
    
    Note over user,vs: Wallet Engagement Phase
    user->>+wallet_app: Scan QR or tap on UL
    wallet_app->>wallet_app: Parse QR
    wallet_app->>+vs: Retrieve session
    vs->>-wallet_app: Return verifier details &<br/>requested attributes
    wallet_app->>-user: Display verifier details<br/>and requested attributes
    
    Note over user,vs: Disclosure Processing Phase
    user->>+wallet_app: Approve disclosure
    wallet_app->>+vs: POST /disclosure/sessions/{session_token}/response_uri<br/>(disclosed attributes)
    vs->>vs: Validate attributes authenticity<br/>and validity
    alt Same Device
        vs->>vs: generate nonce
    end
    vs->>-wallet_app: Success confirmation & https://rp_frontend/redirect_uri&nonce={nonce} in case of Same Device
    wallet_app->>-user: Display success dialog
    
    Note over user,vs: Result Retrieval Phase
    alt Same Device
        wallet_app->>rp_frontend: open<br>https://rp_frontend/redirect_uri&nonce={nonce}
    else Cross Device
        rp_frontend->>rp_frontend: Poll loop notices session is done
    end
    
    rp_frontend->>+rp_backend: Notify backend that session is done<br>[application specific]
    rp_backend->>+vs: GET /disclosure/sessions/{session_token}/disclosed_attributes&nonce={nonce}<br>(nonce included only in case of Same Device flows)
    alt Same Device
        vs->>vs: check nonce
    end
    vs->>-rp_backend: disclosed_attributes
    rp_backend->>rp_backend: Process attributes [application specific]
    rp_backend->>-rp_frontend: Success (token/session) [application specific]
    rp_frontend->>user: Show success [application specific]
```

## Session States

- **CREATED**: Session has been created and is awaiting user action
- **WAITING_FOR_RESPONSE**: User is interacting with wallet, waiting for response
- **DONE**: Session is complete with one of the following substates:
  - **SUCCESS**: Attributes were successfully disclosed and validated
  - **FAILED**: Validation or other infrastructure issues
  - **CANCELED**: User rejected the disclosure request
  - **EXPIRED**: User took too long to respond

## Key API Endpoints

### Private API (Requester)
- `POST /disclosure/sessions` - Initialize a new disclosure session
- `GET /disclosure/sessions/{session_token}/disclosed_attributes` - Retrieve disclosed attributes after successful validation

### Public API (Wallet)
- `GET /disclosure/sessions/{session_token}` - Check session status
- `POST /disclosure/sessions/{session_token}/request_uri` - Device engagement request
- `POST /disclosure/sessions/{session_token}/response_uri` - Device response with disclosed attributes

## Components

- **User**: Person initiating the verification/disclosure
- **RP Frontend**: Relying party's frontend (JavaScript/HTML/CSS), may use wallet_web library
- **RP Backend**: Relying party's backend server
- **Verification Server**: NL Wallet verification server component (OV - Ontvangende Voorziening)
- **NL Wallet App**: NL Wallet mobile application
