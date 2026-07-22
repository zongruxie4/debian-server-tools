#!/bin/bash
#
# Run an isolated HTTP integration test for wordpress.inc.conf.
#

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly WORDPRESS_CONFIG="${SCRIPT_DIR}/wordpress.inc.conf"
readonly APACHE_BINARY="${APACHE_BINARY:-/usr/sbin/apache2}"
readonly TEST_PORT="${WORDPRESS_INC_TEST_PORT:-$((20000 + RANDOM % 30000))}"
readonly TEST_ROOT="$(mktemp -d)"
readonly DOCUMENT_ROOT="${TEST_ROOT}/public"
readonly WORDPRESS_ROOT="${DOCUMENT_ROOT}/site"
readonly APACHE_CONFIG="${TEST_ROOT}/apache.conf"
readonly APACHE_ERROR_LOG="${TEST_ROOT}/apache-error.log"
readonly APACHE_OUTPUT="${TEST_ROOT}/apache-output.log"
readonly BASE_URL="http://127.0.0.1:${TEST_PORT}"

APACHE_PID=""
TEST_COUNT=0
FAILURE_COUNT=0

cleanup() {
    local exit_status=$?

    trap - EXIT

    if [[ -n "${APACHE_PID}" ]] && kill -0 "${APACHE_PID}" 2>/dev/null; then
        kill "${APACHE_PID}" 2>/dev/null || true
        wait "${APACHE_PID}" 2>/dev/null || true
    fi

    rm -rf -- "${TEST_ROOT}"
    exit "${exit_status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

create_fixture() {
    local request_path=$1
    local file_path="${DOCUMENT_ROOT}${request_path}"

    mkdir -p -- "$(dirname -- "${file_path}")"
    : >"${file_path}"
}

assert_status() {
    local expected_status=$1
    local request_path=$2
    local description=$3
    local actual_status

    TEST_COUNT=$((TEST_COUNT + 1))

    if ! actual_status="$(
        curl \
            --globoff \
            --max-time 5 \
            --output /dev/null \
            --path-as-is \
            --silent \
            --write-out '%{http_code}' \
            "${BASE_URL}${request_path}"
    )"; then
        actual_status="000"
    fi

    if [[ "${actual_status}" == "${expected_status}" ]]; then
        printf 'ok %d - %s\n' "${TEST_COUNT}" "${description}"
        return
    fi

    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    printf 'not ok %d - %s (expected %s, got %s for %s)\n' \
        "${TEST_COUNT}" \
        "${description}" \
        "${expected_status}" \
        "${actual_status}" \
        "${request_path}"
}

require_command "${APACHE_BINARY}"
require_command curl

[[ -r "${WORDPRESS_CONFIG}" ]] || fail "Cannot read ${WORDPRESS_CONFIG}"

ALLOWED_PATHS=(
    /index.php
    /site/wp-comments-post.php
    /site/wp-login.php
    /site/wp-admin/admin-ajax.php
    /site/wp-admin/admin-post.php
    /site/wp-admin/admin.php
    /site/wp-admin/async-upload.php
    /site/wp-admin/authorize-application.php
    /site/wp-admin/comment.php
    /site/wp-admin/customize.php
    /site/wp-admin/edit-comments.php
    /site/wp-admin/edit-tags.php
    /site/wp-admin/edit.php
    /site/wp-admin/erase-personal-data.php
    /site/wp-admin/export-personal-data.php
    /site/wp-admin/export.php
    /site/wp-admin/font-library.php
    /site/wp-admin/import.php
    /site/wp-admin/index.php
    /site/wp-admin/load-scripts.php
    /site/wp-admin/load-styles.php
    /site/wp-admin/media-new.php
    /site/wp-admin/media-upload.php
    /site/wp-admin/nav-menus.php
    /site/wp-admin/options-connectors.php
    /site/wp-admin/options-discussion.php
    /site/wp-admin/options-general.php
    /site/wp-admin/options-media.php
    /site/wp-admin/options-permalink.php
    /site/wp-admin/options-privacy.php
    /site/wp-admin/options-reading.php
    /site/wp-admin/options-writing.php
    /site/wp-admin/options.php
    /site/wp-admin/plugin-install.php
    /site/wp-admin/plugins.php
    /site/wp-admin/post-new.php
    /site/wp-admin/post.php
    /site/wp-admin/profile.php
    /site/wp-admin/privacy-policy-guide.php
    /site/wp-admin/privacy.php
    /site/wp-admin/revision.php
    /site/wp-admin/site-editor.php
    /site/wp-admin/site-health.php
    /site/wp-admin/term.php
    /site/wp-admin/theme-install.php
    /site/wp-admin/themes.php
    /site/wp-admin/tools.php
    /site/wp-admin/update-core.php
    /site/wp-admin/update.php
    /site/wp-admin/upgrade.php
    /site/wp-admin/upload.php
    /site/wp-admin/user-edit.php
    /site/wp-admin/user-new.php
    /site/wp-admin/users.php
    /site/wp-admin/widgets.php
)

DENIED_PATHS=(
    /shell.php
    /shell.PHP
    /missing.php
    /wp-content/mu-plugins/index.php
    /wp-content/plugins/demo/direct.php
    /wp-content/themes/demo/direct.php
    /wp-content/uploads/backdoor.php
    /static/plugins/demo/direct.php
    /static/themes/demo/direct.php
    /static/uploads/backdoor.php
    /site/index.php
    /site/wp-blog-header.php
    /site/wp-config.php
    /site/wp-config-sample.php
    /site/wp-cron.php
    /site/wp-links-opml.php
    /site/wp-load.php
    /site/wp-mail.php
    /site/wp-settings.php
    /site/wp-trackback.php
    /site/xmlrpc.php
    /site/wp-admin/install.php
    /site/wp-admin/setup-config.php
    /site/wp-admin/includes/admin.php
    /site/wp-content/plugins/demo/direct.php
    /site/wp-content/themes/demo/direct.php
    /site/wp-content/uploads/backdoor.php
    /site/wp-includes/pluggable.php
)

STATIC_DENIED_PATHS=(
    /readme.txt
    /docs/README.md
    /site/readme.html
    /site/license.txt
    /site/licenc.txt
    /site/olvasdel.html
)

for request_path in "${ALLOWED_PATHS[@]}" "${DENIED_PATHS[@]}" "${STATIC_DENIED_PATHS[@]}"; do
    [[ "${request_path}" == "/missing.php" ]] || create_fixture "${request_path}"
done

create_fixture /assets/style.css
create_fixture /site/wp-content/plugins/allowed/direct.php

mkdir -p -- "${TEST_ROOT}/shared-uploads"
: >"${TEST_ROOT}/shared-uploads/backdoor.php"
mkdir -p -- "${DOCUMENT_ROOT}/wp-content/uploads"
ln -s -- "${TEST_ROOT}/shared-uploads" "${DOCUMENT_ROOT}/wp-content/uploads/shared"

if [[ "$(id -u)" == "0" ]]; then
    APACHE_USER="www-data"
    APACHE_GROUP="www-data"
else
    APACHE_USER="$(id -un)"
    APACHE_GROUP="$(id -gn)"
fi
readonly APACHE_USER APACHE_GROUP

chmod -R a+rX "${TEST_ROOT}"

cat >"${APACHE_CONFIG}" <<APACHE_CONFIG_EOF
LoadModule mpm_event_module /usr/lib/apache2/modules/mod_mpm_event.so
LoadModule authz_core_module /usr/lib/apache2/modules/mod_authz_core.so
LoadModule rewrite_module /usr/lib/apache2/modules/mod_rewrite.so

ServerRoot "/etc/apache2"
ServerName localhost
Listen 127.0.0.1:${TEST_PORT}
PidFile "${TEST_ROOT}/apache.pid"
ErrorLog "${APACHE_ERROR_LOG}"
LogLevel warn
User ${APACHE_USER}
Group ${APACHE_GROUP}

Define DOCUMENT_ROOT "${DOCUMENT_ROOT}"
Define WORDPRESS_ROOT "${WORDPRESS_ROOT}"
Define WORDPRESS_ROOT_URL "/site/"

DocumentRoot "${DOCUMENT_ROOT}"
<Directory "${DOCUMENT_ROOT}">
    AcceptPathInfo On
    AllowOverride None
    Options FollowSymLinks
    Require all granted
</Directory>

Include "${WORDPRESS_CONFIG}"

# Verify that a site-specific exception can restore one required plugin endpoint.
<Location "/site/wp-content/plugins/allowed/direct.php">
    Require all granted
</Location>
APACHE_CONFIG_EOF

"${APACHE_BINARY}" -t -f "${APACHE_CONFIG}"

"${APACHE_BINARY}" -X -f "${APACHE_CONFIG}" >"${APACHE_OUTPUT}" 2>&1 &
APACHE_PID=$!

APACHE_READY=0
for _attempt in {1..50}; do
    if ! kill -0 "${APACHE_PID}" 2>/dev/null; then
        cat "${APACHE_OUTPUT}" >&2 || true
        cat "${APACHE_ERROR_LOG}" >&2 || true
        fail "Apache stopped before accepting requests"
    fi

    if curl --max-time 1 --output /dev/null --silent "${BASE_URL}/index.php"; then
        APACHE_READY=1
        break
    fi

    sleep 0.1
done

if [[ "${APACHE_READY}" != "1" ]]; then
    cat "${APACHE_OUTPUT}" >&2 || true
    cat "${APACHE_ERROR_LOG}" >&2 || true
    fail "Apache did not become ready on ${BASE_URL}"
fi

for request_path in "${ALLOWED_PATHS[@]}"; do
    assert_status 200 "${request_path}" "allow ${request_path}"
done

for request_path in "${DENIED_PATHS[@]}"; do
    assert_status 403 "${request_path}" "deny ${request_path}"
done

for request_path in "${STATIC_DENIED_PATHS[@]}"; do
    assert_status 403 "${request_path}" "deny metadata ${request_path}"
done

assert_status 200 /assets/style.css "serve a normal static file"
assert_status 200 /pretty/permalink "rewrite a permalink to the public index"
assert_status 400 '/?s={search_term_string}' "reject the schema search placeholder"
assert_status 403 /site/wp-config.php/path-info "deny PATH_INFO on a protected PHP file"
assert_status 200 /site/wp-login.php/path-info "allow PATH_INFO on an allowed PHP file"
assert_status 403 /site/wp-login.php/../wp-config.php "normalize traversal before authorization"
assert_status 200 /site/%77p-login.php "allow a normalized encoded entry point"
assert_status 200 /site//wp-login.php "allow a normalized duplicate slash"
assert_status 403 /wp-content/uploads/shared/backdoor.php "deny PHP through an uploads symlink"
assert_status 200 /site/wp-content/plugins/allowed/direct.php "allow a site-specific plugin exception"

TEST_COUNT=$((TEST_COUNT + 1))
CRAWLER_STATUS="$(
    curl \
        --max-time 5 \
        --output /dev/null \
        --path-as-is \
        --silent \
        --user-agent MJ12bot \
        --write-out '%{http_code}' \
        "${BASE_URL}/crawler-path"
)"
if [[ "${CRAWLER_STATUS}" == "301" ]]; then
    printf 'ok %d - add a trailing slash for a configured crawler\n' "${TEST_COUNT}"
else
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    printf 'not ok %d - add a trailing slash for a configured crawler (expected 301, got %s)\n' \
        "${TEST_COUNT}" \
        "${CRAWLER_STATUS}"
fi

printf '1..%d\n' "${TEST_COUNT}"

if [[ "${FAILURE_COUNT}" != "0" ]]; then
    printf '%d of %d tests failed.\n' "${FAILURE_COUNT}" "${TEST_COUNT}" >&2
    exit 1
fi

printf 'All %d tests passed.\n' "${TEST_COUNT}"
