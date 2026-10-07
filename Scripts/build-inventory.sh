#!/usr/bin/env bash
# Génère l'inventaire Kolla-Ansible "multinode" :
#   vos hôtes (Config/multinode.hosts)
#   + groupes de l'inventaire livré avec la version de kolla-ansible installée.
#
# Pourquoi : les groupes de l'inventaire changent d'une version à l'autre.
# Un inventaire copié d'une autre version provoque des erreurs de groupes
# manquants ou inconnus.
#
# Usage (environnement virtuel kolla-ansible activé) :
#   Scripts/build-inventory.sh [fichier_de_sortie]      # défaut : ~/multinode
#
# Variables optionnelles :
#   SHIPPED_INVENTORY  chemin de l'inventaire "multinode" livré (sinon déduit
#                      de $VIRTUAL_ENV)
#   HOSTS_FILE         fichier d'hôtes (défaut : Config/multinode.hosts)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTS_FILE="${HOSTS_FILE:-$REPO_DIR/Config/multinode.hosts}"
OUT_FILE="${1:-$HOME/multinode}"
SHIPPED="${SHIPPED_INVENTORY:-}"

if [[ -z "$SHIPPED" && -n "${VIRTUAL_ENV:-}" ]]; then
  SHIPPED="$VIRTUAL_ENV/share/kolla-ansible/ansible/inventory/multinode"
fi

if [[ -z "$SHIPPED" ]]; then
  echo "ERREUR : environnement virtuel non activé et SHIPPED_INVENTORY non défini." >&2
  echo "         Faites : source ~/kolla-ansible/bin/activate" >&2
  exit 1
fi
if [[ ! -f "$SHIPPED" ]]; then
  echo "ERREUR : inventaire livré introuvable : $SHIPPED" >&2
  exit 1
fi
if [[ ! -f "$HOSTS_FILE" ]]; then
  echo "ERREUR : fichier d'hôtes introuvable : $HOSTS_FILE" >&2
  exit 1
fi
if ! grep -q '^\[baremetal:children\]' "$SHIPPED"; then
  echo "ERREUR : repère [baremetal:children] absent de $SHIPPED." >&2
  echo "         Format d'inventaire inattendu : adaptez le script." >&2
  exit 1
fi

if [[ -e "$OUT_FILE" ]]; then
  BACKUP="${OUT_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$OUT_FILE" "$BACKUP"
  echo "Sauvegarde de l'ancien fichier : $BACKUP"
fi

{
  echo "# Fichier GÉNÉRÉ par Scripts/build-inventory.sh — ne pas éditer à la main."
  echo "# Hôtes      : $HOSTS_FILE"
  echo "# Groupes    : $SHIPPED"
  echo
  tr -d '\r' < "$HOSTS_FILE"
  echo
  # Reprend l'inventaire livré à partir de [baremetal:children], en retirant
  # les blocs [loadbalancer] / [loadbalancer:children] (remplacés par ceux de
  # votre fichier d'hôtes).
  tr -d '\r' < "$SHIPPED" | awk '
    /^\[baremetal:children\]/ { started = 1 }
    !started { next }
    /^\[/ { skip = ($0 ~ /^\[loadbalancer(:children)?\][[:space:]]*$/) }
    !skip { print }
  '
} > "$OUT_FILE"

echo "Inventaire généré : $OUT_FILE ($(wc -l < "$OUT_FILE") lignes)"

if command -v ansible-inventory >/dev/null 2>&1; then
  echo
  echo "Membres du groupe loadbalancer (attendu : controller01..03) :"
  ansible-inventory -i "$OUT_FILE" --graph loadbalancer
else
  echo "ansible-inventory introuvable : vérification du groupe loadbalancer ignorée."
fi
