#!/usr/bin/env bash
# Construit les anneaux (rings) Swift : object, account, container.
#
# À exécuter sur controller01 (nœud de déploiement), APRÈS
# "kolla-ansible bootstrap-servers" (Docker doit être installé) et AVANT
# "kolla-ansible deploy". Les fichiers sont écrits dans /etc/kolla/config/swift.
#
# Variables optionnelles :
#   STORAGE_NODES    IP des nœuds de stockage, séparées par des espaces
#                    (défaut : 172.20.10.8 = storage01)
#   DISKS            nombre de disques Swift par nœud : d0..d(N-1) (défaut : 3)
#   REPLICAS         nombre de réplicas (défaut : 3)
#   PART_POWER       puissance de partition (défaut : 10)
#   OPENSTACK_RELEASE  série Kolla (défaut : 2026.1)
#   KOLLA_SWIFT_BASE_IMAGE  image complète à utiliser. Défaut :
#                    quay.io/openstack.kolla/swift-base:<release>-rocky-10
#   RING_DIR         dossier des anneaux (défaut : /etc/kolla/config/swift)
#   FORCE=1          autorise l'écrasement d'anneaux existants (DESTRUCTIF)
#
# Avec un seul nœud de stockage, les réplicas sont répartis sur les disques
# du même nœud : acceptable en lab, aucune protection contre la perte du nœud.
set -euo pipefail

STORAGE_NODES="${STORAGE_NODES:-172.20.10.8}"
DISKS="${DISKS:-3}"
REPLICAS="${REPLICAS:-3}"
PART_POWER="${PART_POWER:-10}"
OPENSTACK_RELEASE="${OPENSTACK_RELEASE:-2026.1}"
KOLLA_SWIFT_BASE_IMAGE="${KOLLA_SWIFT_BASE_IMAGE:-quay.io/openstack.kolla/swift-base:${OPENSTACK_RELEASE}-rocky-10}"
RING_DIR="${RING_DIR:-/etc/kolla/config/swift}"
MIN_PART_HOURS=1

if ! command -v docker >/dev/null 2>&1; then
  echo "ERREUR : docker introuvable. Lancez d'abord : kolla-ansible bootstrap-servers -i ~/multinode" >&2
  exit 1
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
fi

mkdir -p "$RING_DIR" 2>/dev/null || sudo mkdir -p "$RING_DIR"

if [[ "${FORCE:-0}" != "1" ]]; then
  for ring in object account container; do
    if [[ -e "$RING_DIR/${ring}.builder" ]]; then
      echo "ERREUR : $RING_DIR/${ring}.builder existe déjà." >&2
      echo "         Relancer ce script recréerait des anneaux vides (perte de la" >&2
      echo "         correspondance données/disques). Utilisez FORCE=1 si c'est voulu." >&2
      exit 1
    fi
  done
fi

echo "Image : $KOLLA_SWIFT_BASE_IMAGE"
if ! "${DOCKER[@]}" image inspect "$KOLLA_SWIFT_BASE_IMAGE" >/dev/null 2>&1; then
  if ! "${DOCKER[@]}" pull "$KOLLA_SWIFT_BASE_IMAGE"; then
    echo "ERREUR : impossible de récupérer l'image $KOLLA_SWIFT_BASE_IMAGE." >&2
    echo "         Si le nom ou l'étiquette diffère dans votre version, relevez-le avec" >&2
    echo "         'docker images | grep swift' puis relancez avec :" >&2
    echo "         KOLLA_SWIFT_BASE_IMAGE=<nom:étiquette> $0" >&2
    exit 1
  fi
fi

ring_builder() {
  "${DOCKER[@]}" run --rm \
    -v "$RING_DIR/:$RING_DIR/" \
    "$KOLLA_SWIFT_BASE_IMAGE" swift-ring-builder "$@"
}

# ring:port  (object 6000, account 6001, container 6002)
for spec in object:6000 account:6001 container:6002; do
  ring="${spec%%:*}"
  port="${spec##*:}"
  echo "== $ring (port $port)"
  ring_builder "$RING_DIR/${ring}.builder" create "$PART_POWER" "$REPLICAS" "$MIN_PART_HOURS"
  for node in $STORAGE_NODES; do
    for ((i = 0; i < DISKS; i++)); do
      ring_builder "$RING_DIR/${ring}.builder" add "r1z1-${node}:${port}/d${i}" 1
    done
  done
done

# Rééquilibrage
for ring in object account container; do
  ring_builder "$RING_DIR/${ring}.builder" rebalance
done

# Les fichiers sont créés par root (conteneur) : les rendre lisibles par
# l'utilisateur qui lance kolla-ansible.
sudo chown -R "$(id -u):$(id -g)" "$RING_DIR" 2>/dev/null || true

echo "Terminé. Fichiers :"
ls -l "$RING_DIR"
