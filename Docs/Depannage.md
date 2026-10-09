# Dépannage

Problèmes rencontrés pendant le déploiement de ce lab (Kolla-Ansible 2026.1, Rocky Linux 10.2) et solutions. Les sorties citées viennent du lab réel du 08/10/2026.

Sommaire : [dnf](#dnf--nothing-provides-openssl-libs) · [Images introuvables](#image-introuvable--manifest-unknown) · [pull unreachable](#kolla-ansible-pull--unreachable) · [Avertissement inventaire](#avertissement--invalid-characters-were-found-in-group-names) · [NFS](#montage-nfs-glance) · [SELinux](#selinux) · [Docker](#version-de-docker) · [Cinder](#cinder--groupes-et-contrôle) · [RAM](#ram-insuffisante) · [Précheck](#précheck--erreurs-rencontrées)

---

## dnf : `nothing provides openssl-libs`

**Symptôme** (étape 8.1) :

```
nothing provides openssl-libs(x86-64) = 1:3.5.8-2.el10_2 needed by openssl-devel-1:3.5.8-2.el10_2.x86_64 from appstream
```

**Cause.** Le dépôt AppStream propose une version de `openssl-devel` qui exige exactement la même version de `openssl-libs`, absente du dépôt BaseOS : les miroirs sont temporairement désynchronisés, ou le cache est périmé.

**Solution.** Rafraîchir le cache, puis relancer l'installation :

```bash
sudo dnf clean all
sudo dnf makecache
sudo dnf update -y
sudo dnf install -y git python3-devel libffi-devel gcc openssl-devel python3-libselinux
```

Cette séquence a résolu le problème dans ce lab. Si l'erreur persiste : `dnf --showduplicates list openssl-libs openssl-devel`, puis attendre la synchronisation du miroir ou en changer (`mirrorlist` / `baseurl` dans `/etc/yum.repos.d/rocky*.repo`). Évitez `--skip-broken` : il ignorerait `openssl-devel`.

---

## Image introuvable : `manifest unknown`

**Symptôme.**

```
Error response from daemon: manifest for quay.io/openstack.kolla/swift-base:2026.1-rocky-10 not found: manifest unknown
```

**Cause.** L'étiquette n'existe pas sur quay.io. Pour Swift, aucune image n'est publiée pour la série 2026.1 (relevé du 08/10/2026), alors que les autres services le sont :

| Image | Étiquettes observées sur quay.io |
|-------|----------------------------------|
| `nova-api`, `keystone` | `2025.1-rocky-10`, `2025.2-rocky-10`, `2026.1-rocky-10`, `2026.2-rocky-10` |
| `swift-base`, `swift-proxy-server` | `2024.2-rocky-9` seulement |

**Solution retenue.** Swift est désactivé (`enable_swift: "no"`) et la sauvegarde Cinder, qui utilisait Swift, l'est aussi (`enable_cinder_backup: "no"`) :

```bash
sed -i \
  -e 's/^enable_swift:.*/enable_swift: "no"/' \
  -e 's/^enable_cinder_backup:.*/enable_cinder_backup: "no"/' \
  -e 's/^cinder_backup_driver:/# cinder_backup_driver:/' \
  /etc/kolla/globals.yml
```

**Comment vérifier qu'une image existe, et quelle étiquette Kolla utilisera :**

```bash
# Étiquette construite par Kolla : <release>-<distro>-<version de la distro>
grep -rn "openstack_tag" $VIRTUAL_ENV/share/kolla-ansible/ansible/group_vars/

# Étiquettes publiées pour une image (remplacer nova-api)
curl -s 'https://quay.io/api/v1/repository/openstack.kolla/nova-api/tag/?limit=100&onlyActiveTags=true' \
  | python3 -c "import sys,json; print('\n'.join(sorted({t['name'] for t in json.load(sys.stdin)['tags']})))" \
  | grep -E '2026|rocky'
```

Dans les versions récentes, `group_vars/all.yml` est un dossier `group_vars/all/` : d'où le `grep -r`.

`kolla-ansible pull -i ~/multinode` (étape 11.2) vérifie l'ensemble des images utiles avant le déploiement. Si une autre image manque, désactivez le service concerné dans `globals.yml`.

---

## `kolla-ansible pull` : `unreachable`

**Symptôme.** Dans le `PLAY RECAP`, un nœud affiche `unreachable=1` et la commande se termine par `exited 4`. Les autres nœuds ont `failed=0`.

**Cause.** Ansible a perdu la connexion SSH vers ce nœud en cours de route : ce n'est pas une erreur de configuration. Les images de ce nœud n'ont pas été vérifiées.

**Solution.**

```bash
ping -c 3 network01
ssh kolla@network01 "uptime; df -h /var/lib/docker; free -h; ip -br a"
kolla-ansible pull -i ~/multinode      # reprenable : les images déjà présentes ne sont pas retéléchargées
```

À vérifier si cela se reproduit : VM éteinte ou figée dans VMware, coupure réseau passagère (carte en mode Bridged, surtout via Wi-Fi), disque ou mémoire saturés, IP changée (`ens160` doit être en `manual`). Le message exact se trouve sur la ligne `fatal: [<nœud>]: UNREACHABLE!` plus haut dans la sortie.

---

## Avertissement : `Invalid characters were found in group names`

```
[WARNING]: Invalid characters were found in group names but not replaced, use -vvvv to see details
```

Normal : les noms de groupes de l'inventaire Kolla contiennent des tirets. Les commandes `ansible-inventory` et `kolla-ansible` fonctionnent ; l'avertissement peut être ignoré.

---

## Montage NFS Glance

**Symptôme.** `mount` échoue ou se bloque, ou `df -h /mnt/glance` montre un disque local.

**Cause fréquente : mauvaise IP dans `/etc/fstab`.** L'IP doit être celle de `storage01` (`172.20.10.10` dans ce lab). Dans une première version de ce guide, le tableau d'architecture donnait `172.20.10.8`, qui est en réalité `compute01` (pas un serveur NFS). Contrôle :

```bash
grep glance /etc/fstab
showmount -e 172.20.10.10    # doit lister /srv/nfs/glance
df -h /mnt/glance            # doit montrer 172.20.10.10:/srv/nfs/glance
```

Correction si `fstab` contient une mauvaise IP :

```bash
sudo sed -i 's#172.20.10.8:/srv/nfs/glance#172.20.10.10:/srv/nfs/glance#' /etc/fstab
sudo umount -l /mnt/glance 2>/dev/null
sudo mount -a
df -h /mnt/glance
```

Relancez ensuite le test du fichier `test-partage` entre les 3 contrôleurs (étape 6.3). Pour trouver l'IP réelle d'un nœud : `hostname -I` sur ce nœud.

---

## SELinux

Sur les **3 contrôleurs uniquement** :

```bash
sudo setsebool -P virt_use_nfs on
getsebool virt_use_nfs                # virt_use_nfs --> on
sudo ausearch -m avc -ts recent       # "<no matches>" = aucun refus enregistré
```

`ausearch` demande `sudo` pour lire les journaux d'audit. Un résultat `<no matches>` avant le déploiement est normal : Glance n'est pas encore lancé.

---

## Version de Docker

`docker_yum_package_pin: "3:28.*"` n'a eu aucun effet : `bootstrap-servers` a installé Docker **29.8.2** sur Rocky Linux 10. Le pin a été retiré de `globals.yml`. Cette version a passé `bootstrap-servers` et `pull` ; `prechecks` et `deploy` diront si elle est pleinement acceptée.

---

## Cinder : groupes et contrôle

Avec Kolla-Ansible 2026.1, l'inventaire généré contient :

```ini
[cinder-volume:children]      # groupe générique : rattaché aux contrôleurs
cinder

[cinder-volume-lvm:children]  # backend LVM : rattaché à storage
storage
```

`ansible-inventory -i ~/multinode --graph cinder-volume-lvm` doit donc montrer `storage01` (et non `cinder-volume`, qui montre les contrôleurs). Contrôle après déploiement :

```bash
source /etc/kolla/admin-openrc.sh
openstack volume service list
```

**Précheck « Multiple cinder-volume instances detected but cinder_cluster_name is not set ».** Le groupe `cinder-volume-multiple` regroupe `cinder` (contrôleurs) et `storage` (`storage01`) : 4 hôtes, d'où l'erreur. N'ajoutez pas `cinder_cluster_name` : un cluster Cinder suppose un stockage partagé, pas un LVM local. Solution retenue : `cinder_cluster_skip_precheck: true` dans `globals.yml` (à retirer avec Ceph). Si, après `deploy`, un `cinder-volume` d'un contrôleur est sans backend ou `down`, l'inventaire sera à ajuster.

Attendu : `cinder-scheduler` sur les contrôleurs et un `cinder-volume` sur `storage01`, tous `up`. Si un `cinder-volume` est `down` sur un contrôleur, il n'a pas de volume group (`cinder-volumes` n'existe que sur `storage01`) : ouvrez un ticket avec la sortie de `docker logs cinder_volume` sur ce contrôleur avant de modifier l'inventaire.

---

## RAM insuffisante

**Constat** (08/10/2026) : contrôleurs 3,8 Go, `network01`, `compute01` et `storage01` 1,9 Go, soit bien moins que le plan d'origine (24 Go et 16 Go). Les contrôleurs n'avaient déjà plus que 2,6 Go disponibles avant tout déploiement.

**Risque.** Au `deploy`, MariaDB, RabbitMQ et tous les services OpenStack démarrent sur chaque contrôleur : à mon estimation, des conteneurs risquent d'être tués par manque de mémoire (OOM) et le cluster d'être instable. `compute01` à 1,9 Go ne peut pas héberger de VM utile.

**Solution.** Éteindre les VMs et augmenter la RAM dans VMware avant `deploy`. Ordres de grandeur pour un lab (estimation, à adapter à la RAM du PC hôte) : contrôleurs 8–12 Go, `compute01` 6–8 Go, `network01` et `storage01` 3–4 Go. Pour alléger les contrôleurs, désactivez au besoin Magnum, Designate, Barbican, Grafana et Prometheus dans `globals.yml`.

Après redémarrage : `ssh kolla@<nœud> "free -h"`.

**Avec 32 Go sur le PC hôte** (estimation de lab, à ajuster) : contrôleurs 5–6 Go, `compute01` 4 Go, `network01` 3 Go, `storage01` 2,5 Go (≈ 25,5 Go au total), en mettant `enable_prometheus`, `enable_grafana`, `enable_barbican`, `enable_magnum` et `enable_designate` à `"no"`. Ajouter 2 Go de swap par VM évite qu'un pic tue un conteneur. Dans VMware : « Fit all virtual machine memory into reserved host RAM ». Activer la virtualisation imbriquée sur `compute01`, sinon `nova_compute_virt_type: "qemu"` (très lent).

---

## Précheck : erreurs rencontrées

Sorties du lab du 09/10/2026, dans l'ordre où elles sont apparues. `prechecks` est passé sur les 7 hôtes (`failed=0`) après les trois corrections.

| Message | Cause | Solution |
|---------|-------|----------|
| `kolla_external_vip_address and kolla_internal_vip_address must not be the same when only one network has TLS enabled` | VIP unique avec TLS sur un seul réseau | `kolla_enable_tls_external: "yes"` en plus de l'interne, puis `kolla-ansible certificates -i ~/multinode` ; contrôle : `haproxy.pem` et `haproxy-internal.pem` dans `/etc/kolla/certificates/` |
| `Kolla images from quay.io/openstack.kolla namespace are meant only for testing purposes ... --use-test-images` | Les images de quay.io sont publiées pour les tests | `kolla-ansible prechecks -i ~/multinode --use-test-images` (idem pour `deploy` si demandé). En production : images construites et registre privé |
| `Multiple cinder-volume instances detected but cinder_cluster_name is not set` | Voir [Cinder](#cinder--groupes-et-contrôle) | `cinder_cluster_skip_precheck: true` |
