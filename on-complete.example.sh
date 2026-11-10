#!/bin/bash
set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

# Protocole : sftp ou ftp
PROTOCOL="sftp"

# Serveur distant
REMOTE_HOST="192.168.2.10"
REMOTE_PORT="22"
REMOTE_USER="utilisateur"
REMOTE_PASSWORD="mot_de_passe"

# Authentification par clé SSH (optionnelle)
USE_SSH_KEY="false"
SSH_KEY="/home/container/.ssh/id_ed25519"
KNOWN_HOSTS="/home/container/.ssh/known_hosts"

# Répertoire distant
REMOTE_DIR="/incoming"

# Transferts simultanés
PARALLEL=2

# ============================================================
# NE RIEN MODIFIER EN DESSOUS SAUF SI NECESSAIRE
# ============================================================

log() {
    printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# Vérification du protocole
case "${PROTOCOL}" in
    sftp)
        DEFAULT_PORT=22
        ;;
    ftp)
        DEFAULT_PORT=21
        ;;
    *)
        log "ERREUR : protocole inconnu : ${PROTOCOL}"
        exit 1
        ;;
esac

# Vérification des paramètres
if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ]; then
    log "ERREUR : configuration du serveur distant incomplète."
    exit 1
fi

REMOTE_PORT="${REMOTE_PORT:-${DEFAULT_PORT}}"

if ! [[ "${REMOTE_PORT}" =~ ^[0-9]+$ ]] || \
   [ "${REMOTE_PORT}" -lt 1 ] || [ "${REMOTE_PORT}" -gt 65535 ]; then
    log "ERREUR : port distant invalide."
    exit 1
fi

if ! [[ "${PARALLEL}" =~ ^[1-9][0-9]*$ ]]; then
    log "ERREUR : PARALLEL doit être un entier positif."
    exit 1
fi

if ! command -v lftp >/dev/null 2>&1; then
    log "ERREUR : lftp n'est pas installé."
    exit 1
fi

# Vérification de l'authentification
case "${PROTOCOL}" in
    sftp)
        if [ ! -f "${SSH_KEY}" ]; then
            log "ERREUR : clé privée SSH introuvable : ${SSH_KEY}"
            exit 1
        fi

        if [ ! -s "${KNOWN_HOSTS}" ]; then
            log "ERREUR : fichier known_hosts absent ou vide."
            exit 1
        fi

        # Permissions nécessaires à OpenSSH
        mkdir -p "$(dirname "${SSH_KEY}")"
        chmod 700 "$(dirname "${SSH_KEY}")"
        chmod 600 "${SSH_KEY}"
        chmod 644 "${KNOWN_HOSTS}"
        ;;

    ftp)
        if [ -z "${REMOTE_PASSWORD}" ]; then
            log "ERREUR : mot de passe FTP non renseigné."
            exit 1
        fi
        ;;
esac

# Récupération du chemin du téléchargement terminé
LOCAL_PATH="${TR_TORRENT_DIR:?}/${TR_TORRENT_NAME:?}"

if [ ! -e "${LOCAL_PATH}" ]; then
    log "ERREUR : fichier ou dossier introuvable : ${LOCAL_PATH}"
    exit 1
fi

# Préparation du chemin distant
REMOTE_DIR="${REMOTE_DIR%/}"

if [ -d "${LOCAL_PATH}" ]; then
    REMOTE_TARGET="${REMOTE_DIR}/${TR_TORRENT_NAME}"
else
    REMOTE_TARGET="${REMOTE_DIR:-/}"
fi

# Échappement des valeurs pour le langage de commandes lftp
lftp_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    printf '"%s"' "${value}"
}

# Fichier temporaire contenant les commandes lftp
umask 077
LFTP_COMMANDS="$(mktemp)"
trap 'rm -f "${LFTP_COMMANDS}"' EXIT

{
    printf 'set cmd:fail-exit yes\n'
    printf 'set net:max-retries 2\n'
    printf 'set net:timeout 30\n'

    if [ "${PROTOCOL}" = "sftp" ]; then
        printf 'set sftp:auto-confirm no\n'

        printf 'set sftp:connect-program "ssh -a -x -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%s"\n' \
            "${SSH_KEY}" \
            "${KNOWN_HOSTS}"

        printf 'open -u %s %s\n' \
            "$(lftp_quote "${REMOTE_USER}")" \
            "$(lftp_quote "sftp://${REMOTE_HOST}:${REMOTE_PORT}")"
    else
        printf 'open -u %s,%s %s\n' \
            "$(lftp_quote "${REMOTE_USER}")" \
            "$(lftp_quote "${REMOTE_PASSWORD}")" \
            "$(lftp_quote "ftp://${REMOTE_HOST}:${REMOTE_PORT}")"
    fi


    if [ -d "${LOCAL_PATH}" ]; then
    		printf 'mkdir -p %s\n' "$(lftp_quote "${REMOTE_TARGET}")"
        printf 'mirror --reverse --verbose --continue --parallel=%s %s %s\n' \
            "${PARALLEL}" \
            "$(lftp_quote "${LOCAL_PATH}")" \
            "$(lftp_quote "${REMOTE_TARGET}")"
    else
        printf 'put -O %s %s\n' \
            "$(lftp_quote "${REMOTE_TARGET}")" \
            "$(lftp_quote "${LOCAL_PATH}")"
    fi

    printf 'bye\n'
} > "${LFTP_COMMANDS}"

log "Début de l'upload : ${TR_TORRENT_NAME}"
log "Destination : ${PROTOCOL}://${REMOTE_HOST}:${REMOTE_PORT}${REMOTE_TARGET}"

lftp -f "${LFTP_COMMANDS}"

log "Upload terminé : ${TR_TORRENT_NAME}"
