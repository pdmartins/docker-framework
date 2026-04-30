#!/usr/bin/env bash
# hooks/backup-volumes.sh
#
# Executado em background pelo post-commit.
# Recebe: REPO_ROOT seguido dos diretórios a fazer backup.
# Gera zips com máxima compressão em partes de 5MB em .backup-volumes/{nome}/
# e cria um commit git por volume.

set -eo pipefail

REPO_ROOT="$1"; shift
BACKUP_DIR="${REPO_ROOT}/.backup-volumes"
LOG_FILE="${BACKUP_DIR}/backup.log"
LOCK_FILE="${BACKUP_DIR}/backup.lock"

mkdir -p "$BACKUP_DIR"

# Cria lock para evitar execução dupla
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

log "========================================"
log "Backup iniciado (PID $$)"
log "Diretórios: $*"
log "========================================"

cd "$REPO_ROOT"

for parent_rel in "$@"; do
  volumes_dir="${REPO_ROOT}/${parent_rel}/volumes"
  parent_abs="${REPO_ROOT}/${parent_rel}"

  # Pula volumes vazios ou inexistentes
  if [[ ! -d "$volumes_dir" ]] || [[ -z "$(ls -A "$volumes_dir" 2>/dev/null)" ]]; then
    log "Ignorando volume vazio ou inexistente: ${parent_rel}/volumes"
    continue
  fi

  base_name="${parent_rel//\//-}-volumes"   # ex: platform-sonarqube-volumes
  dest_dir="${BACKUP_DIR}/${base_name}"

  log "Iniciando: ${parent_rel}/volumes → .backup-volumes/${base_name}/"

  # Limpa partes antigas para evitar arquivos obsoletos (.z01, .z02, etc.)
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"

  # Cria zip com máxima compressão (-9) e split de 5MB (-s 5m)
  # cd no dest_dir é necessário: zip cria os .z01/.z02 no diretório corrente
  # Exit code 18 = arquivos sem permissão (esperado em volumes Docker) — trata como aviso
  log "Compactando..."
  zip_output=$(cd "$dest_dir" && zip -r -9 -s 5m "${base_name}.zip" "${parent_abs}/volumes/" 2>&1)
  zip_exit=$?

  if [[ $zip_exit -eq 0 ]]; then
    size=$(du -sh "$dest_dir" | cut -f1)
    log "OK: .backup-volumes/${base_name}/ (${size})"
  elif [[ $zip_exit -eq 18 ]]; then
    size=$(du -sh "$dest_dir" | cut -f1)
    log "AVISO: alguns arquivos sem permissão ignorados em ${parent_rel}/volumes (${size})"
  else
    log "ERRO ao criar zip de ${parent_rel}/volumes (exit $zip_exit):"
    log "$zip_output"
    continue
  fi

  # Adiciona apenas esta pasta de backup e cria um commit dedicado
  git -C "$REPO_ROOT" add "${dest_dir}"
  git -C "$REPO_ROOT" commit -m "chore: backup volumes - ${parent_rel}"
  log "Commit criado: backup volumes - ${parent_rel}"
  log "----------------------------------------"
done

log "Backup concluído."
