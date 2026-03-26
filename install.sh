#! /bin/bash

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
DOCKER_DIR="${SCRIPT_DIR}/docker"

export OPENCLAW_GATEWAY_PORT=18789
export OPENCLAW_BRIDGE_PORT=18790

# load env
set -a; source "${SCRIPT_DIR}/env"; set +a

if [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
    FORCE_INSTALL=1
fi

# >>>>>>>>>> install brew & node.js
which brew > /dev/null 2>&1
if [ $? -ne 0 ] || [ ${FORCE_INSTALL:-0} -eq 1 ]; then
    echo "==> Installing HomeBrew..."
    pushd "${HOME}" > /dev/null 2>&1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo "==> Installing Node.js..."
    brew install node@24  # Download and install Node.js:
    corepack enable pnpm  # Download and install pnpm:
    popd > /dev/null 2>&1
fi

# >>>>>>>>>> install openclaw
echo "==> Installing OpenClaw..."

# install openclaw
export NODE_USE_ENV_PROXY=1
#npm install -g openclaw@latest
npm install -g openclaw@${OPENCLAW_VERSION:-latest}
openclaw onboard --install-daemon

# patch service
systemctl --user stop openclaw-gateway
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/env.conf <<EOF
[Service]
Environment="NODE_USE_ENV_PROXY=1"
Environment="OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-claw}"
EOF
systemctl --user daemon-reload

# patch for lan access
openclaw config set gateway.mode local
openclaw config set gateway.bind lan

# >>>>>>>>>> configure allowedOrigins
echo "==> Configure allowedOrigins ..."
URLS=""
if [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
    HTTPS_PORT=${OPENCLAW_GATEWAY_HTTPS_PORT:-443}
    URLS="$(printf ,\"https://%s:${HTTPS_PORT}\" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
    URLS="$URLS$(printf ,\"http://%s:${OPENCLAW_GATEWAY_PORT}\" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
    if [ ${HTTPS_PORT} -eq 443 ]; then
        # for 443, also allow urls without port
        URLS="$URLS$(printf ,\"https://%s\" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
    fi
fi
URLS="[\"http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\",\"http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}\"${URLS}]"
openclaw config set gateway.controlUi.allowedOrigins \
    "${URLS}" \
    --strict-json

# >>>>>>>>>> install Feishu
if [ ${CONFIG_FEISHU:-0} -eq 1 ]; then
    echo "==> Installing Feishu"
    source "${SCRIPT_DIR}/scripts/json_utils.sh"
    if [ -n "${FEISHU_APP_ID:-}" ] && [ -n "${FEISHU_APP_SECRET:-}" ]; then
        echo "==> Configure Feishu with app_id & app_secret & allow_from ..."
        FEISHU_CHANNEL_JSON="$(json_object \
            $(json_field_common "enabled" true) \
            $(json_field_string "appId" "${FEISHU_APP_ID:-}") \
            $(json_field_string "appSecret" "${FEISHU_APP_SECRET:-}") \
            $(json_field_string "domain" "feishu") \
            $(json_field_string "connectionMode" "websocket") \
            $(json_field_common "requireMention" true) \
            $(json_field_string "dmPolicy" "allowlist") \
            $(json_field_array_string_no_empty "allowFrom" "${FEISHU_ALLOW_FROM:-}") \
            $(json_field_string "groupPolicy" "open") \
            $(json_field_array_common "groupAllowFrom") \
            $(json_field_common "streaming" true) \
            $(json_field_common "threadSession" true) \
            $(json_field_common "footer" $(json_object \
                $(json_field_common "elapsed" true) \
                $(json_field_common "status" true) \
            )) \
        )"
        openclaw config set channels.feishu "${FEISHU_CHANNEL_JSON}"  --strict-json
    fi

    echo "==> Installing Feishu ..."
    pushd "${HOME}" > /dev/null 2>&1
    npx -y @larksuite/openclaw-lark install
    popd > /dev/null 2>&1
fi

# >>>>>>>>>> start caddy if needed
if [ ${ENABLE_CADDY:-0} -eq 1 ]; then
    echo "==> Prepare Caddyfile ..."
    CADDY_CONF_DIR="$DOCKER_DIR/caddy_conf"
    CADDY_FILE="$CADDY_CONF_DIR/Caddyfile"
    mkdir -p "${CADDY_CONF_DIR}"
    if [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
        echo "  --> Generating Caddyfile ..."
        CADDY_URLS="$(printf ", %s" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
        echo "{" > "${CADDY_FILE}"
        echo "      default_sni 127.0.0.1"  >> "${CADDY_FILE}"
        echo "}" >> "${CADDY_FILE}"
        echo "127.0.0.1${CADDY_URLS} {" >> "${CADDY_FILE}"
        echo "      tls internal" >> "${CADDY_FILE}"
        echo "      reverse_proxy 192.168.3.200:${OPENCLAW_GATEWAY_PORT}" >> "${CADDY_FILE}"
        echo "}" >> "${CADDY_FILE}"
    else
        echo "  --> Skip Caddyfile due to OPENCLAW_GATEWAY_ALLOWED_IP not set or empty ..."
    fi

    pushd "${DOCKER_DIR}" > /dev/null 2>&1
    docker compose -f docker-compose.caddy.yml up -d
    popd > /dev/null 2>&1
fi

# >>>>>>>>>> start gateway
systemctl --user start openclaw-gateway
