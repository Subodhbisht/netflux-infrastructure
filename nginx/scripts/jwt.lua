-- Helper function for Base64URL decoding
local function base64url_decode(input)
    if not input then return nil end
    local remainder = #input % 4
    if remainder > 0 then
        input = input .. string.rep("=", 4 - remainder)
    end
    input = string.gsub(input, "-", "+")
    input = string.gsub(input, "_", "/")
    return ngx.decode_base64(input)
end

-- 1. Grab pre-parsed public key from global worker memory
local pubkey = _G.PUBLIC_KEY
if not pubkey then
    ngx.log(ngx.ERR, "Public key missing from worker memory")
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- 2. Get the Authorization Header
local auth_header = ngx.var.http_authorization
if not auth_header then
    ngx.log(ngx.ERR, "Missing Authorization Header")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- 3. Extract the token from "Bearer <token>"
local token = string.match(auth_header, "Bearer%s+(.+)")
if not token then
    ngx.log(ngx.ERR, "Invalid Bearer Token Format")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- 4. Split token into 3 distinct parts (Header.Payload.Signature)
local parts = {}
for part in string.gmatch(token, "[^%.]+") do
    table.insert(parts, part)
end

if #parts ~= 3 then
    ngx.log(ngx.ERR, "Malformed JWT structure: expected 3 parts, got ", #parts)
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local header_b64, payload_b64, sig_b64 = parts[1], parts[2], parts[3]

-- 5. Cryptographic RS256 Signature Verification
-- The signed message is strictly "Header.Payload"
local message = header_b64 .. "." .. payload_b64
local signature = base64url_decode(sig_b64)

if not signature then
    ngx.log(ngx.ERR, "Failed to base64url decode JWT signature")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- Verify RS256 (RSASSA-PKCS1-v1_5 + SHA-256) signature against the RSA public key
local ok, verify_err = pubkey:verify(signature, message, "sha256")
if not ok then
    ngx.log(ngx.ERR, "JWT Signature Verification Failed: ", verify_err)
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- 6. Extract Claims
local payload_json = base64url_decode(payload_b64)
if not payload_json then
    ngx.log(ngx.ERR, "Base64 Decoding Failed for Payload")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local sub = string.match(payload_json, '"sub"%s*:%s*"([^"]+)"')
if not sub then
    -- Fallback check if sub is numeric
    sub = string.match(payload_json, '"sub"%s*:%s*(%d+)')
end

if not sub then
    ngx.log(ngx.ERR, "Could not find sub claim in JWT payload: ", payload_json)
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- 7. Pass extracted user_id upstream
ngx.var.user_id = sub