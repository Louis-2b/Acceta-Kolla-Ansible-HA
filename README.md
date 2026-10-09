# Déploiement OpenStack HA avec Kolla-Ansible

<p align="center">
  <img src="Images/Openstack_Logo.jpeg" alt="OpenStack Logo" width="500"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OpenStack-2026.1%20Gazpacho-red?style=for-the-badge&logo=openstack" alt="OpenStack 2026.1 Gazpacho"/>
  <img src="https://img.shields.io/badge/Rocky%20Linux-10.2-green?style=for-the-badge&logo=rockylinux" alt="Rocky Linux 10.2"/>
  <img src="https://img.shields.io/badge/Kolla--Ansible-Multinode-blue?style=for-the-badge&logo=ansible" alt="Kolla-Ansible Multinode"/>
  <img src="https://img.shields.io/badge/Docker-Conteneurs-2496ED?style=for-the-badge&logo=docker" alt="Docker"/>
</p>

---

## Table des matières

- [Présentation](#présentation)
- [Prérequis](#prérequis)
- [Environnement de test](#environnement-de-test)
- [Architecture du déploiement](#architecture-du-déploiement)
- [Rôles des nœuds](#rôles-des-nœuds)
  - [Contrôleurs](#contrôleurs--controller01-controller02-controller03)
  - [Réseau](#réseau--network01)
  - [Calcul](#calcul--compute01)
  - [Stockage](#stockage--storage01)
- [Interfaces réseau](#interfaces-réseau)
- [Services déployés](#services-déployés)
- [Étape 1 — Création de la VM de base](#étape-1--création-de-la-vm-de-base)
- [Étape 2 — Installation de Rocky Linux 10.2](#étape-2--installation-de-rocky-linux-102)
- [Étape 3 — Configuration post-installation](#étape-3--configuration-post-installation)
- [Étape 4 — Clonage et personnalisation des nœuds](#étape-4--clonage-et-personnalisation-des-nœuds)
- [Étape 5 — Configuration spécifique par rôle](#étape-5--configuration-spécifique-par-rôle)
- [Étape 6 — Partage NFS pour Glance](#étape-6--partage-nfs-pour-glance)
- [Étape 7 — Accès SSH sans mot de passe](#étape-7--accès-ssh-sans-mot-de-passe)
- [Étape 8 — Installation de Kolla-Ansible](#étape-8--installation-de-kolla-ansible)
- [Étape 9 — Configuration de Kolla-Ansible](#étape-9--configuration-de-kolla-ansible)
- [Étape 10 — Génération des certificats TLS](#étape-10--génération-des-certificats-tls)
- [Étape 11 — Déploiement d'OpenStack](#étape-11--déploiement-dopenstack)
- [Étape 12 — Post-déploiement et vérification](#étape-12--post-déploiement-et-vérification)
- [Étape 13 — Créer et distribuer des tenants](#étape-13--créer-et-distribuer-des-tenants)
- [Référence — Fichiers importants](#référence--fichiers-importants)
- [Documentation complémentaire](#documentation-complémentaire)

---

## Présentation

Ce projet documente le déploiement complet d'un environnement **cloud OpenStack à haute disponibilité (HA)** à l'aide de **Kolla-Ansible** sur **Rocky Linux 10.2**.

L'infrastructure repose sur les composants suivants :

- Architecture multi-nœuds : contrôleurs, calcul, réseau, stockage
- Conteneurisation complète avec **Docker**
- Cluster **Galera** + **HAProxy** + **Keepalived** pour la haute disponibilité
- Configuration centralisée via **Ansible**
- Machines virtuelles provisionnées sous **VMware Workstation**

> **Version cible : OpenStack 2026.1 (Gazpacho).** La série 2024.2 est en fin de vie depuis le 29/04/2026 et ne supporte pas Rocky Linux 10. Détails et sources : [`Docs/Corrections.md`](Docs/Corrections.md).
>
> **Périmètre de la haute disponibilité.** Le plan de contrôle (API, MariaDB Galera, RabbitMQ, HAProxy/Keepalived) est en HA sur 3 contrôleurs. Les nœuds réseau, calcul et stockage de cette topologie sont uniques : ce n'est pas encore une plateforme HA de bout en bout. Voir [`Docs/HA-Roadmap.md`](Docs/HA-Roadmap.md).

> Ce guide s'adresse aux ingénieurs **DevOps**, aux architectes **cloud** et aux administrateurs système avancés souhaitant reproduire ce déploiement en laboratoire ou en production.

---

## Prérequis

Avant de commencer, assurez-vous de maîtriser les bases de :

- Administration **Linux** (gestion des utilisateurs, systemd, partitions)
- **Réseaux** (interfaces, routage, VLAN)
- **Ansible** (inventaires, playbooks, rôles)

---

## Environnement de test

| Composant | Version / Détail |
|-----------|-----------------|
| Système d'exploitation | Rocky Linux 10.2 (ISO minimal) |
| Plateforme cloud | OpenStack 2026.1 (Gazpacho) |
| Outil de déploiement | Kolla-Ansible (`stable/2026.1`) |
| Moteur de conteneurs | Docker |
| Hyperviseur | VMware Workstation |
| Orchestrateur | Ansible |

---

## Architecture du déploiement

Le cluster est composé de **6 nœuds** provisionnés sous VMware Workstation. Une VM de base (`controller01`) a été créée puis clonée pour produire les nœuds supplémentaires. Chaque nœud fonctionne sous **Rocky Linux 10.2 (ISO minimal)**.

| Nom d'hôte | Rôle | IPv4 | vCPU | RAM mesurée | RAM recommandée (lab) | Disque racine | Notes |
|------------|------|------|------|-------------|-----------------------|---------------|-------|
| `controller01` | Contrôleur | 172.20.10.3 | 4 | 3,8 Go | 8–12 Go | 35 Go | Nœud de déploiement Kolla |
| `controller02` | Contrôleur | 172.20.10.6 | 4 | 3,8 Go | 8–12 Go | 35 Go | |
| `controller03` | Contrôleur | 172.20.10.7 | 4 | 3,8 Go | 8–12 Go | 35 Go | |
| `compute01` | Calcul | 172.20.10.8 | 4 | 1,9 Go | 6–8 Go | 35 Go | Virtualisation imbriquée activée |
| `network01` | Réseau | 172.20.10.9 | 4 | 1,9 Go | 3–4 Go | 35 Go | |
| `storage01` | Stockage | 172.20.10.10 | 4 | 1,9 Go | 3–4 Go | 35 Go | Disque LVM pour Cinder, serveur NFS pour Glance |

Les colonnes « mesurée » et « disque racine » viennent des commandes `nproc`, `free -h` et `df -h /` lancées sur chaque nœud le 08/10/2026. Les adresses sont celles relevées avec `hostname -I`.

> ⚠️ **RAM recommandée = estimation de lab**, pas une valeur de la documentation Kolla : à ajuster à la mémoire de votre PC hôte. Un contrôleur fait tourner MariaDB, RabbitMQ et tous les services OpenStack : avec 3,8 Go, il est probable que des conteneurs soient tués par manque de mémoire. Augmentez la RAM des VMs (éteintes) **avant** `kolla-ansible deploy`.

**VIP (HAProxy + Keepalived)** : `172.20.10.14`, FQDN `openstack.tubie.lan`. Elle doit rester libre (aucun nœud ne la porte en statique) et appartenir au même sous-réseau que `ens160`.

> ⚠️ **Règle de quorum HA :** Les nœuds contrôleurs doivent toujours être en **nombre impair** (3, 5, 7…) afin que le cluster MariaDB Galera et Keepalived puissent élire un leader en cas de défaillance.

---

## Rôles des nœuds

### Contrôleurs — `controller01`, `controller02`, `controller03`

Les nœuds de contrôle forment le **plan de contrôle** du cloud OpenStack. Ils hébergent toutes les API, la base de données, la messagerie et l'équilibrage de charge.

| Service | Description |
|---------|-------------|
| `Keystone` | Gestion des identités et authentification |
| `Glance` | Catalogue d'images (stockage partagé sur `/mnt/glance`) |
| `Nova API / Scheduler / Conductor` | Gestion des ressources de calcul |
| `Neutron Server` | API réseau |
| `Horizon` | Interface web (Dashboard) |
| `MariaDB (Galera)` | Base de données en cluster HA |
| `RabbitMQ` | File d'attente de messages (HA) |
| `Memcached` | Cache de sessions |
| `HAProxy + Keepalived` | Équilibrage de charge et VIP haute disponibilité |
| `Prometheus + Grafana` | Monitoring et métriques |

---

### Réseau — `network01`

Le nœud réseau gère toute la connectivité des instances.

| Service | Description |
|---------|-------------|
| `Neutron OVS Agent` | Réseaux overlay (VXLAN / GRE) |
| `Neutron L3 Agent` | Routage inter-réseaux et NAT |
| `Neutron DHCP Agent` | Attribution d'adresses IP aux instances |
| `Neutron Metadata Agent` | Fourniture de métadonnées aux instances |

---

### Calcul — `compute01`

Le nœud de calcul exécute les machines virtuelles des locataires (tenants).

| Service | Description |
|---------|-------------|
| `Nova Compute` | Cycle de vie des VMs |
| `Libvirt / KVM` | Hyperviseur pour l'exécution des VMs |
| `Neutron OVS Agent` | Connectivité réseau des VMs |
| `Prometheus Node Exporter` | Monitoring des ressources du nœud |

---

### Stockage — `storage01`

Le nœud de stockage fournit du stockage persistant en mode bloc, et sert le partage NFS utilisé par Glance.

| Service | Description |
|---------|-------------|
| `Cinder Volume` | Volumes bloc (backend LVM, groupe d'inventaire `cinder-volume-lvm`) |
| `LVM` | Gestion des volumes logiques (`cinder-volumes`) |
| `iscsid / tgtd` | Services iSCSI pour les volumes Cinder |
| `Serveur NFS` | Partage `/srv/nfs/glance`, monté par les contrôleurs (images Glance) |
| `Prometheus Node Exporter` | Monitoring des ressources du nœud |

---

## Interfaces réseau

Chaque nœud dispose d'**au moins deux interfaces réseau** :

| Interface | Rôle | Configuration |
|-----------|------|---------------|
| `ens160` | Réseau de gestion (API, réplication, stockage) | IP statique |
| `ens192` | Réseau externe (IPs flottantes, provider networks) | Sans adresse IP — géré par Neutron (OVS bridge) |

> ⚠️ Les noms d'interfaces (`ens160`, `ens192`) peuvent varier selon la configuration de l'hyperviseur. Vérifiez toujours avec `ip a` après création ou clonage d'une VM.

---

## Services déployés

Le déploiement est découpé en phases : la phase 1 est activée par défaut dans [`Config/globals.yml`](Config/globals.yml) ; la phase 2 est prête à être décommentée une fois la phase 1 validée.

### Phase 1 — activés

| Service | Description |
|---------|-------------|
| **Keystone** | Authentification et identité |
| **Glance** | Catalogue d'images (stockage partagé NFS `/mnt/glance`) |
| **Nova** | Service de calcul |
| **Neutron** | Service réseau (ML2/Open vSwitch) |
| **Horizon** | Dashboard web |
| **Heat** | Orchestration (stacks) |
| **Cinder** | Stockage bloc (LVM) |
| **Barbican** | Gestion des secrets et chiffrement |
| **Magnum** | Orchestration Kubernetes (clusters K8s) |
| **Designate** | DNS as a Service (bind9) |
| **HAProxy + Keepalived** | Équilibrage de charge et VIP |
| **MariaDB (Galera), RabbitMQ, Memcached, Valkey, etcd** | Services d'infrastructure |
| **Prometheus + Grafana** | Collecte et visualisation des métriques |

### Phase 2 — désactivés (blocs prêts dans `globals.yml`)

| Service | Raison | Prérequis |
|---------|--------|-----------|
| **Octavia** | Load Balancer as a Service | Image `amphora` construite et téléversée, réseau de gestion `lb-mgmt-net`, certificats Octavia |
| **Ceilometer / Aodh / Gnocchi** | Télémétrie | Backend Gnocchi partagé (Ceph) : le backend `file` est incohérent avec 3 contrôleurs |

### Retirés

| Service | Raison |
|---------|--------|
| **Zun** | Supprimé de Kolla-Ansible en 2026.1 (« Zun is broken in 2026.1 ») |
| **Kuryr** | Supprimé de Kolla-Ansible en 2026.1 |
| **Swift** | Les images conteneur ne sont pas publiées sur quay.io pour 2026.1 (voir [`Docs/Depannage.md`](Docs/Depannage.md)) |
| **Sauvegarde Cinder** | Utilisait Swift comme destination ; à remettre avec un autre backend (NFS, Ceph, S3) |

---

## Étape 1 — Création de la VM de base

Créez une VM de référence (`controller01`) qui servira de base pour le clonage de tous les autres nœuds.

### 1.1 Ressources matérielles

| Paramètre | Valeur recommandée |
|-----------|-------------------|
| vCPU | 4 (minimum 2) |
| RAM | 16 Go (minimum 8 Go) |
| Disque | 60 Go+ |
| Type de disque | Thin Provision |

> **Thin Provision** : le fichier du disque virtuel ne grossit qu'avec les données réellement écrites, au lieu de réserver toute la taille d'un coup. C'est pratique pour 6 VMs, mais laissez de la marge sur le disque du PC hôte : s'il se remplit, les VMs peuvent se figer.

![Spécifications de la VM](Images/Pic-01.png)

### 1.2 Configuration réseau

Ajoutez **deux cartes réseau** à la VM :

| NIC | Mode VMware | Rôle OpenStack |
|-----|-------------|----------------|
| NIC 1 (`ens160`) | Bridged | API, réplication, stockage |
| NIC 2 (`ens192`) | Bridged | Provider networks, IPs flottantes |

![Ajout NIC 1](Images/Pic-02.png)
![Ajout NIC 2](Images/Pic-03.png)
![Résumé de configuration](Images/Pic-04.png)

---

## Étape 2 — Installation de Rocky Linux 10.2

> **Télécharger l'ISO Rocky Linux 10.2 (minimal) :** [https://rockylinux.org/download](https://rockylinux.org/download)

Démarrez la VM et lancez l'installation.

![Démarrage de l'installation](Images/Pic-05.png)

### 2.1 Langue d'installation

Sélectionnez la langue souhaitée (le Français est supporté).

![Choix de la langue](Images/Pic-06.png)

### 2.2 Paramètres à configurer

| Paramètre | Recommandation |
|-----------|----------------|
| Partitionnement | Automatique ou manuel (LVM recommandé) |
| Réseau et nom d'hôte | Configurer `ens160` et `ens192` |
| Fuseau horaire | Votre région |
| Mot de passe root | Fort, noté en lieu sûr |
| Utilisateur dédié | `kolla` |

![Écran de configuration](Images/Pic-07.png)

### 2.3 Configuration réseau

- **`ens160`** : Activez le DHCP pour l'instant — l'IP statique sera configurée après installation.
- **`ens192`** : Désactivez entièrement IPv4. Cette interface sera gérée exclusivement par Neutron (OVS bridge) et **ne doit pas avoir d'adresse IP système**.

![Configuration NIC 1](Images/Pic-10.png)
![Configuration NIC 2](Images/Pic-11.png)
![Activation de l'interface](Images/Pic-12.png)

Validez et lancez l'installation.

![Lancement de l'installation](Images/Pic-14.png)

---

## Étape 3 — Configuration post-installation

Une fois Rocky Linux installé et la VM redémarrée, effectuez les opérations suivantes **en tant que `root`** sur `controller01`, **avant tout clonage**.

### 3.1 Mise à jour du système

```bash
sudo dnf update -y
```

### 3.2 Création et configuration de l'utilisateur `kolla`

L'utilisateur `kolla` exécutera Kolla-Ansible sur tous les nœuds. Il doit disposer de droits `sudo` sans mot de passe (requis pour les tâches d'élévation de privilèges Ansible).

```bash
# Ajout au groupe wheel (sudo)
usermod -aG wheel kolla

# Vérification
grep wheel /etc/group
```

Configurez ensuite `sudo` sans mot de passe pour le groupe `wheel` :

```bash
# Vérification syntaxique préalable
sudo visudo -c

# Modification de sudoers :
# - Commente  : %wheel ALL=(ALL) ALL
# - Décommente : %wheel ALL=(ALL) NOPASSWD: ALL
sudo sed -i \
  -e 's/^\s*%wheel\s*ALL=(ALL)\s*ALL\s*$/# &/' \
  -e 's/^\s*#\s*%wheel\s*ALL=(ALL)\s*NOPASSWD:\s*ALL\s*$/%wheel ALL=(ALL) NOPASSWD: ALL/' \
  /etc/sudoers

# Vérification syntaxique après modification — ne pas sauter cette étape
sudo visudo -c
```

### 3.3 Installation des paquets prérequis

```bash
# Outils d'archivage requis pour certains rôles Ansible
sudo dnf install -y tar gzip unzip

# OpenSSL requis pour la génération des certificats TLS
sudo dnf install -y openssl
```

### 3.4 Vérification des interfaces réseau

```bash
# Affichage de toutes les interfaces et adresses IP
ip a

# Affichage compact (nom + état + adresse IPv4)
ip -br -4 addr show
```

**Résultat attendu :**
- `ens160` — UP, avec une adresse IP (DHCP temporaire)
- `ens192` — UP ou DOWN, **sans adresse IP**

---

## Étape 4 — Clonage et personnalisation des nœuds

### 4.1 Clonage de la VM de base

1. Éteignez `controller01` avant de cloner.
2. Utilisez l'option **clonage entièrement indépendant** dans VMware.

![Clonage étape 1](Images/Pic-15.png)
![Clonage étape 2](Images/Pic-16.png)
![Clonage étape 3](Images/Pic-17.png)
![Clonage étape 4](Images/Pic-18.png)
![Clonage étape 5](Images/Pic-19.png)

3. Répétez pour créer : `controller02`, `controller03`, `compute01`, `network01`, `storage01`.

![Architecture complète](Images/Pic-20.png)

### 4.2 Nom d'hôte et adresse IP statique

À réaliser sur **chaque nœud** après clonage.

**Définir le nom d'hôte :**

```bash
sudo hostnamectl set-hostname <hostname>
hostname  # validation
```

**Régénérer l'identité machine (recommandé sur les clones) :**

Les clones partagent le `machine-id` et les clés d'hôte SSH de la VM d'origine, ce qui peut provoquer des conflits d'identifiant (DHCP, journaux) et des avertissements SSH. À faire **avant** l'étape 7.

```bash
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
sudo systemd-machine-id-setup
sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo systemctl restart sshd
cat /etc/machine-id   # doit être différent sur chaque nœud
```

**Configurer l'IP statique sur `ens160` :**

```bash
nmcli device status

sudo nmcli con mod ens160 ipv4.addresses 172.20.10.X/28
sudo nmcli con mod ens160 ipv4.gateway 172.20.10.1
sudo nmcli con mod ens160 ipv4.dns '8.8.8.8 1.1.1.1'
sudo nmcli con mod ens160 ipv4.method manual

sudo nmcli con down ens160 && sudo nmcli con up ens160
ip a show ens160  # validation
```

> Remplacez `172.20.10.X` par l'adresse IP correspondant au nœud (voir [tableau d'architecture](#architecture-du-déploiement)).

Vérifiez que l'adresse est bien **statique**. En DHCP, elle peut changer au redémarrage et casser le cluster :

```bash
nmcli -g ipv4.method con show ens160   # doit afficher : manual
```

### 4.3 Fichier `/etc/hosts` sur `controller01`

`controller01` est le nœud de déploiement Kolla-Ansible. Ce fichier lui permet de résoudre tous les nœuds par nom d'hôte. Les entrées DNS sur les autres nœuds seront propagées par Ansible.

```bash
sudo nano /etc/hosts
```

Ajoutez les entrées suivantes :

```text
172.20.10.3   controller01
172.20.10.6   controller02
172.20.10.7   controller03
172.20.10.8   compute01
172.20.10.9   network01
172.20.10.10  storage01
```

Vérifiez la connectivité vers tous les nœuds :

```bash
for host in controller01 controller02 controller03 compute01 network01 storage01; do
  ping -c 1 $host >/dev/null && echo "$host : OK" || echo "$host : UNREACHABLE"
done
```

---

## Étape 5 — Configuration spécifique par rôle

### 5.1 Activer la virtualisation imbriquée sur `compute01`

La virtualisation imbriquée est requise pour que KVM fonctionne à l'intérieur d'une VM VMware.

1. Ouvrez les paramètres de la VM `compute01`.
2. Activez l'option de virtualisation dans les paramètres du processeur.

![Paramètres compute01](Images/Pic-21.png)
![Activation virtualisation imbriquée](Images/Pic-22.png)

> Si vous disposez de plusieurs nœuds de calcul (`compute02`, etc.), répétez l'opération pour chacun.

### 5.2 Attacher et préparer les disques de stockage sur `storage01`

Cinder (stockage bloc) nécessite un disque dédié :

- **1 disque de 20 Go** pour Cinder (volume LVM)

> Swift est désactivé avec 2026.1 (voir [`Docs/Depannage.md`](Docs/Depannage.md)) : les 3 disques Swift prévus à l'origine ne sont plus nécessaires. Si vous les avez déjà ajoutés, laissez-les inutilisés.

**Ajouter les disques virtuels dans VMware :**

![Ajout disque étape 1](Images/Pic-23.png)
![Ajout disque étape 2](Images/Pic-24.png)
![Ajout disque étape 3](Images/Pic-25.png)
![Ajout disque étape 4](Images/Pic-26.png)
![Ajout disque étape 5](Images/Pic-27.png)
![Ajout disque étape 6](Images/Pic-28.png)

**Vérifier la détection des disques :**

```bash
lsblk
```

**Résultat attendu :** un disque libre et sans partition pour Cinder (`nvme0n2` dans cet exemple).

**Initialiser le volume LVM pour Cinder :**

```bash
sudo pvcreate /dev/nvme0n2
sudo vgcreate cinder-volumes /dev/nvme0n2
sudo vgs  # validation
```

> Adaptez `/dev/nvme0n2` au nom de disque détecté par `lsblk` sur votre système.

### 5.3 Disques Swift (non requis)

Les images conteneur Swift n'étant pas publiées pour 2026.1, Swift est désactivé (`enable_swift: "no"`) et il n'y a **aucun disque Swift à préparer**. Ne formatez pas de disque pour cet usage.

---

## Étape 6 — Partage NFS pour Glance

Les trois contrôleurs doivent partager un répertoire commun `/mnt/glance` pour que le service Glance fonctionne en HA. `storage01` joue le rôle de serveur NFS.

> ⚠️ Ce montage constitue un point de défaillance unique. Il est suffisant pour un environnement de lab, mais une solution redondante (NAS/SAN) est recommandée en production.

### 6.1 Configurer le serveur NFS sur `storage01`

```bash
sudo dnf install -y nfs-utils

sudo mkdir -p /srv/nfs/glance
sudo chmod 755 /srv/nfs/glance

# Exporter le partage vers le réseau de management (sous-réseau /28)
echo "/srv/nfs/glance 172.20.10.0/28(rw,sync,no_subtree_check,no_root_squash)" | \
  sudo tee -a /etc/exports

sudo systemctl enable --now nfs-server
sudo exportfs -ra
sudo exportfs -v  # vérification

# Ouvrir le pare-feu
sudo firewall-cmd --permanent \
  --add-service=nfs \
  --add-service=rpc-bind \
  --add-service=mountd
sudo firewall-cmd --reload
```

> `no_root_squash` est requis : Ansible doit pouvoir corriger les permissions de ce dossier en tant que `root` lors du déploiement de Glance. Sans cette option, le conteneur `glance-api` échouera à écrire dans le répertoire.

> Les images Glance sont écrites sur le disque racine de `storage01` (35 Go mesurés) : surveillez l'espace avec `df -h /srv/nfs/glance` avant de téléverser plusieurs images.

### 6.2 Monter le partage sur les trois contrôleurs

À répéter sur **`controller01`**, **`controller02`** et **`controller03`** :

```bash
sudo dnf install -y nfs-utils

sudo mkdir -p /mnt/glance

# Format : <IP de storage01>:<dossier exporté> <point de montage> nfs <options> 0 0
echo "172.20.10.10:/srv/nfs/glance /mnt/glance nfs defaults,_netdev 0 0" | \
  sudo tee -a /etc/fstab

sudo mount -a
df -h /mnt/glance  # doit afficher 172.20.10.10:/srv/nfs/glance, pas le disque local
```

**Que mettre dans cette ligne ?**

| Champ | Valeur | Explication |
|-------|--------|-------------|
| `172.20.10.10:/srv/nfs/glance` | IP de `storage01` + dossier exporté | Le serveur NFS est `storage01`, le dossier est celui créé à l'étape 6.1 |
| `/mnt/glance` | Point de montage local | Même chemin que `glance_file_datadir_volume` dans `globals.yml` |
| `_netdev` | Option | Attend que le réseau soit disponible avant de monter |

> ⚠️ Utilisez l'**IP réelle de `storage01`** (`hostname -I` sur `storage01`), pas celle d'un autre nœud : le tableau d'architecture donne `172.20.10.10`. Utilisez l'IP plutôt que le nom : à ce stade, seul `controller01` résout les noms de nœuds (étape 4.3).

Vérifiez que le serveur répond avant de monter :

```bash
showmount -e 172.20.10.10   # doit lister /srv/nfs/glance
```

### 6.3 Vérifier le partage entre les nœuds

```bash
# Depuis controller01
sudo touch /mnt/glance/test-partage

# Depuis controller02 et controller03
ls -la /mnt/glance/test-partage  # doit être visible sur les deux nœuds

# Nettoyage
sudo rm /mnt/glance/test-partage
```

> ⚠️ Si le fichier n'est pas visible sur les autres contrôleurs, **ne lancez pas `kolla-ansible deploy`** — le partage n'est pas correctement configuré.

### 6.4 SELinux sur Rocky Linux

À faire **uniquement sur les 3 contrôleurs** : ce sont eux qui montent `/mnt/glance` et font tourner le conteneur `glance-api`. `storage01` (serveur NFS), `network01` et `compute01` n'ont rien à faire.

Si SELinux est en mode `enforcing` (par défaut), le bind-mount NFS vers les conteneurs peut être bloqué. Vous pouvez activer l'autorisation dès maintenant, sans risque, avant `kolla-ansible deploy` :

```bash
# Autoriser l'accès NFS par les conteneurs virtuels (sur chaque contrôleur)
sudo setsebool -P virt_use_nfs on
getsebool virt_use_nfs        # attendu : virt_use_nfs --> on
```

En cas d'erreurs de permission côté `glance-api` après déploiement malgré un montage fonctionnel, diagnostiquez les refus SELinux sur le contrôleur concerné :

```bash
sudo ausearch -m avc -ts recent   # "<no matches>" = aucun refus enregistré
```

---

## Étape 7 — Accès SSH sans mot de passe

Kolla-Ansible se connecte en SSH à chaque nœud depuis `controller01` avec l'utilisateur `kolla`. L'accès sans mot de passe est obligatoire pour que les playbooks Ansible puissent opérer sans interruption.

Toutes les commandes de cette section sont à exécuter **en tant que `kolla`** sur `controller01`.

### 7.1 Générer la paire de clés SSH

```bash
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
```

L'option `-N ""` crée une clé sans passphrase, ce qui est nécessaire pour l'automatisation Ansible.

### 7.2 Déployer la clé publique sur tous les nœuds

```bash
for host in controller01 controller02 controller03 compute01 network01 storage01; do
  ssh-copy-id kolla@$host
done
```

> 📌 Le mot de passe de l'utilisateur `kolla` vous sera demandé une fois par nœud.

### 7.3 Vérifier l'accès sans mot de passe

```bash
for host in controller01 controller02 controller03 compute01 network01 storage01; do
  ssh -o BatchMode=yes kolla@$host "echo '$host : OK'" || echo "$host : ÉCHEC"
done
```

Tous les nœuds doivent répondre sans demande de mot de passe. En cas d'échec, vérifiez que le service SSH est actif sur le nœud concerné et que la clé a bien été copiée.

---

## Étape 8 — Installation de Kolla-Ansible

Toutes les commandes de cette étape sont exécutées sur **`controller01`**, qui orchestre le déploiement de l'ensemble du cluster OpenStack.

### 8.1 Installer les dépendances système

```bash
sudo dnf update -y

sudo dnf install -y \
  git \
  python3-devel \
  libffi-devel \
  gcc \
  openssl-devel \
  python3-libselinux
```

> ⚠️ Si `dnf` répond `nothing provides openssl-libs ... needed by openssl-devel`, les dépôts BaseOS et AppStream sont temporairement désynchronisés (miroir en retard). Rafraîchissez les métadonnées puis relancez l'installation :
>
> ```bash
> sudo dnf clean all && sudo dnf makecache && sudo dnf update -y
> ```
>
> N'utilisez pas `--skip-broken` : il ignorerait `openssl-devel`. Voir [`Docs/Depannage.md`](Docs/Depannage.md).

### 8.2 Créer un environnement virtuel Python

Un environnement virtuel isole les dépendances de Kolla-Ansible du système afin d'éviter tout conflit de paquets.

```bash
# Créer et activer l'environnement virtuel
python3 -m venv ~/kolla-ansible
source ~/kolla-ansible/bin/activate

# Mettre à jour pip
pip install --upgrade pip
```

> ℹ️ L'environnement virtuel doit être activé (`source ~/kolla-ansible/bin/activate`) à chaque nouvelle session avant d'utiliser les commandes `kolla-ansible` ou `ansible`.

### 8.3 Installer Ansible

```bash
pip install 'ansible-core>=2.19,<2.21'
```

> Kolla-Ansible 2026.1 requiert Ansible 12 à 13, soit ansible-core 2.19 à 2.20.

Créez ensuite le fichier de configuration Ansible :

```bash
cat > ~/ansible.cfg << 'EOF'
[defaults]
host_key_checking = False
pipelining        = True
forks             = 100
EOF
```

**Vérification :**

```bash
ansible --version
```

### 8.4 Installer Kolla-Ansible

```bash
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2026.1
```

> ⚠️ Installez bien la branche `stable/2026.1`. Un simple `pip install kolla-ansible` peut installer une autre série que celle ciblée par `globals.yml` (openstack_release), ce qui provoque des variables et des groupes d'inventaire incohérents.

### 8.5 Initialiser la configuration

```bash
# Créer le répertoire de configuration
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla

# Copier les fichiers de configuration d'exemple (globals.yml, passwords.yml)
cp -r $VIRTUAL_ENV/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

> ℹ️ L'inventaire `multinode` n'est pas copié à la main : il est généré à l'étape 9.3 à partir de l'inventaire livré avec la version installée (`$VIRTUAL_ENV/share/kolla-ansible/ansible/inventory/multinode`) et de vos hôtes.

### 8.6 Installer les dépendances Ansible Galaxy

```bash
kolla-ansible install-deps
```

**Vérification finale :**

```bash
kolla-ansible --version
ansible --version
```

---

## Étape 9 — Configuration de Kolla-Ansible

Kolla-Ansible repose sur trois fichiers de configuration principaux. Les deux premiers se trouvent dans `/etc/kolla/`, le troisième est l'inventaire Ansible.

### 9.1 `globals.yml` — Configuration principale

Ce fichier contrôle l'ensemble du comportement du déploiement : VIP, interfaces réseau, services activés, backends de stockage, etc.

> **Fichier de référence :** [`Config/globals.yml`](Config/globals.yml)

Récupérez le dépôt sur `controller01`, puis copiez le fichier :

```bash
git clone https://github.com/Louis-2b/Acceta-Kolla-Ansible-HA.git ~/Acceta-Kolla-Ansible-HA
cp ~/Acceta-Kolla-Ansible-HA/Config/globals.yml /etc/kolla/globals.yml
nano /etc/kolla/globals.yml
```

Adaptez au minimum les paramètres suivants à votre environnement :

| Paramètre | Description | Exemple |
|-----------|-------------|---------|
| `kolla_internal_vip_address` | IP virtuelle (VIP) HAProxy, libre dans le sous-réseau | `172.20.10.14` |
| `kolla_external_fqdn` | Nom DNS de la VIP (voir 9.4) | `openstack.tubie.lan` |
| `openstack_release` | Doit correspondre à la branche de kolla-ansible installée | `2026.1` |
| `network_interface` | Interface de gestion | `ens160` |
| `neutron_external_interface` | Interface réseau externe (sans IP) | `ens192` |
| `kolla_base_distro` | Distribution de base des conteneurs | `rocky` |

---

### 9.2 `passwords.yml` — Mots de passe des services

Ce fichier contient les mots de passe de tous les services OpenStack (base de données, RabbitMQ, Keystone, etc.). Il est généré automatiquement avec la commande suivante :

```bash
kolla-genpwd
```

> ⚠️ Ne commitez jamais ce fichier dans un dépôt public. Conservez-en une copie sécurisée hors du dépôt.

---

### 9.3 Inventaire `multinode` — Assignation des rôles

Les quelque 300 groupes de l'inventaire dépendent de la version de Kolla-Ansible. Copier un inventaire d'une autre version provoque des erreurs de groupes manquants ou inconnus. Le dépôt ne contient donc que **vos hôtes** ([`Config/multinode.hosts`](Config/multinode.hosts)) ; le script [`Scripts/build-inventory.sh`](Scripts/build-inventory.sh) les assemble avec l'inventaire livré avec la version installée, et place HAProxy/Keepalived sur les 3 contrôleurs.

```bash
source ~/kolla-ansible/bin/activate
~/Acceta-Kolla-Ansible-HA/Scripts/build-inventory.sh ~/multinode
```

Vérifiez les rôles avant tout déploiement :

```bash
ansible-inventory -i ~/multinode --graph loadbalancer   # controller01..03
ansible-inventory -i ~/multinode --graph mariadb        # controller01..03
ansible-inventory -i ~/multinode --graph cinder-volume-lvm  # storage01
```

> L'avertissement `Invalid characters were found in group names but not replaced` est normal : les noms de groupes Kolla contiennent des tirets. Vous pouvez l'ignorer.

> Avec Kolla-Ansible 2026.1, le groupe générique `cinder-volume` est rattaché aux contrôleurs, alors que le backend LVM utilise le groupe dédié `cinder-volume-lvm`, rattaché à `storage` (là où se trouve le volume group `cinder-volumes`). Contrôle après déploiement : `openstack volume service list` (étape 12.4).

Pour ajouter un nœud (`network02`, `compute02`...), éditez [`Config/multinode.hosts`](Config/multinode.hosts), puis relancez le script.

---

### 9.4 Entrée DNS locale pour la VIP

Ajoutez l'entrée de résolution de la VIP dans `/etc/hosts` sur **les 6 nœuds**, et sur votre poste de travail si vous souhaitez accéder à Horizon depuis un navigateur.

Depuis `controller01` (nécessite l'accès SSH sans mot de passe de l'étape 7), la boucle suivante n'ajoute la ligne que si elle n'existe pas déjà :

```bash
# kolla_internal_vip_address + kolla_external_fqdn (globals.yml)
for h in controller01 controller02 controller03 network01 compute01 storage01; do
  ssh kolla@$h "grep -q 'openstack.tubie.lan' /etc/hosts || echo '172.20.10.14   openstack.tubie.lan' | sudo tee -a /etc/hosts >/dev/null"
done

# Vérification
for h in controller01 controller02 controller03 network01 compute01 storage01; do
  echo -n "$h : "; ssh kolla@$h "grep openstack.tubie.lan /etc/hosts"
done
```

Sur votre poste de travail, ajoutez la même ligne dans `/etc/hosts` (Linux, macOS) ou dans `C:\Windows\System32\drivers\etc\hosts` (Windows, éditeur lancé en administrateur).

> La VIP `172.20.10.14` doit rester libre : aucun nœud ne doit l'avoir configurée en statique. Si vous la modifiez dans `globals.yml`, mettez à jour cette entrée et régénérez les certificats.

---

## Étape 10 — Génération des certificats TLS

Kolla-Ansible génère les certificats TLS nécessaires à la sécurisation des API OpenStack (VIP).

La commande s'exécute **sur `controller01`** (nœud de déploiement), avec l'environnement virtuel activé, et non sur les autres nœuds : les certificats sont distribués par `deploy`. Prérequis : `kolla-genpwd` exécuté (étape 9.2) et `globals.yml` en place dans `/etc/kolla/`.

```bash
# Certificats TLS pour tous les services OpenStack (CA privée de test)
kolla-ansible certificates -i ~/multinode
```

Les certificats générés sont stockés dans `/etc/kolla/certificates/` (la CA est dans `/etc/kolla/certificates/ca/root.crt`). Vérifiez-les :

```bash
ls -l /etc/kolla/certificates/ /etc/kolla/certificates/ca/   # haproxy.pem, haproxy-internal.pem et ca/root.crt
```

Gardez une copie de `root.crt` et de `passwords.yml` **hors des nœuds** (jamais dans le dépôt GitHub) : `root.crt` doit être remis aux navigateurs et aux clients des tenants.

> ℹ️ La VIP interne et externe étant la même adresse, le précheck exige que le TLS soit activé **sur les deux réseaux** (`kolla_enable_tls_internal` et `kolla_enable_tls_external` à `"yes"`). Avec un seul des deux, `prechecks` échoue. Si vous modifiez ces variables après avoir généré les certificats, relancez `kolla-ansible certificates` : `haproxy.pem` (externe) et `haproxy-internal.pem` doivent exister.

> ⚠️ La CA générée est une CA de test, suffisante pour un lab. Avant d'ouvrir le cloud à d'autres personnes, remplacez-la par une CA interne ou des certificats gérés à l'extérieur (`kolla_externally_managed_cert`).

Si vous activez Octavia (phase 2), générez aussi ses certificats : `kolla-ansible octavia-certificates -i ~/multinode` (fichiers dans `/etc/kolla/config/octavia/`).

---

## Étape 11 — Déploiement d'OpenStack

Le déploiement s'effectue en cinq commandes successives, toujours depuis `controller01` avec l'environnement virtuel activé.

```bash
source ~/kolla-ansible/bin/activate
```

### 11.1 Initialisation des serveurs

Prépare tous les nœuds (installation de Docker, configuration des répertoires Kolla, etc.) :

```bash
kolla-ansible bootstrap-servers -i ~/multinode
```

Contrôlez ensuite la version de Docker installée avec `docker --version` (Docker 29.8.2 observé sur Rocky Linux 10) : aucun pin de version n'est appliqué.

<!-- ![Bootstrap des serveurs](Images/Pic-29.png) — capture à ajouter -->

### 11.2 Pré-téléchargement des images

Chaque service OpenStack tourne dans un conteneur Docker : l'image doit être présente sur le nœud qui l'exécute. `pull` télécharge sur chaque nœud **uniquement les images des services de son rôle** (d'après l'inventaire) et signale les images introuvables **avant** le déploiement.

```bash
df -h /var/lib/docker          # vérifier l'espace disque, surtout sur les contrôleurs
kolla-ansible pull -i ~/multinode
```

- Si un nœud est `unreachable` (code de sortie 4), vérifiez qu'il répond (`ping`, `ssh`) puis relancez : la commande est reprenable.
- Si une image est introuvable (`manifest unknown`), voir [`Docs/Depannage.md`](Docs/Depannage.md).

### 11.3 Vérifications préalables

Valide la configuration avant le déploiement (interfaces, ressources, connectivité) :

```bash
kolla-ansible prechecks -i ~/multinode --use-test-images
```

> ℹ️ `--use-test-images` est obligatoire tant que les images viennent de `quay.io/openstack.kolla`, que le projet Kolla publie « pour les tests ». En production, construisez vos images et utilisez un registre privé (voir [`Docs/HA-Roadmap.md`](Docs/HA-Roadmap.md)). Autres blocages rencontrés au précheck : [`Docs/Depannage.md`](Docs/Depannage.md#précheck--erreurs-rencontrées).

<!-- ![Vérifications préalables](Images/Pic-30.png) — capture à ajouter -->

> ⚠️ Ne passez pas à l'étape suivante si des erreurs sont signalées. Corrigez-les d'abord.

### 11.4 Déploiement

Lance le déploiement complet de l'infrastructure OpenStack :

```bash
kolla-ansible deploy -i ~/multinode --use-test-images
```

Lancez-le dans `tmux` pour qu'une coupure SSH ne l'interrompe pas. Il est reprenable : relancé après un échec, il reprend où il s'est arrêté. Si l'option est refusée par cette commande, retirez-la (`kolla-ansible deploy --help`).

<!-- ![Déploiement OpenStack](Images/Pic-31.png) — capture à ajouter -->

Cette étape peut prendre **30 à 60 minutes** selon les ressources disponibles.

### 11.5 Validation de la configuration

Vérifie que tous les services sont correctement configurés après déploiement :

```bash
kolla-ansible validate-config -i ~/multinode
```

<!-- ![Validation de la configuration](Images/Pic-32.png) — capture à ajouter -->

---

## Étape 12 — Post-déploiement et vérification

### 12.1 Générer le fichier d'authentification

La commande `post-deploy` génère les fichiers `clouds.yaml` et `admin-openrc.sh` utilisés pour interagir avec l'API OpenStack :

```bash
kolla-ansible post-deploy
```

<!-- ![Post-déploiement](Images/Pic-33.png) — capture à ajouter -->

Vérifiez la présence des fichiers :

```bash
ls /etc/kolla/clouds.yaml /etc/kolla/admin-openrc.sh
```

### 12.2 Installer le client OpenStack

```bash
pip install python-openstackclient \
  -c https://releases.openstack.org/constraints/upper/2026.1
```

### 12.3 Charger les variables d'environnement

```bash
source /etc/kolla/admin-openrc.sh
```

<!-- ![Chargement des variables](Images/Pic-35.png) — capture à ajouter -->

### 12.4 Vérifier l'état des services

```bash
# Lister tous les services enregistrés dans Keystone
openstack service list
```

<!-- ![Liste des services](Images/Pic-34.png) — capture à ajouter -->

```bash
# Vérifier l'état des nœuds de calcul
openstack compute service list
```

```bash
# Vérifier Cinder : cinder-scheduler sur les contrôleurs, cinder-volume sur storage01, tous "up"
openstack volume service list
```

> Si un `cinder-volume` apparaît en `down` sur un contrôleur, voir [`Docs/Depannage.md`](Docs/Depannage.md).

### 12.5 Accéder au tableau de bord Horizon

Ouvrez un navigateur sur le FQDN de la VIP (entrée `/etc/hosts` de l'étape 9.4) :

```
https://openstack.tubie.lan
```

> Le TLS utilise la CA privée générée à l'étape 10 : le navigateur affichera un avertissement tant que `/etc/kolla/certificates/ca/root.crt` n'est pas importé comme autorité de confiance. Le client en ligne de commande utilise cette CA via `admin-openrc.sh` (`kolla_admin_openrc_cacert`).

Identifiants de connexion :

| Champ | Valeur |
|-------|--------|
| Nom d'utilisateur | `admin` |
| Mot de passe | Obtenu avec la commande ci-dessous |

```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```

<!-- ![Écran de connexion Horizon](Images/Pic-36.png) — capture à ajouter -->
<!-- ![Tableau de bord Horizon](Images/Pic-37.png) — capture à ajouter -->
<!-- ![Vue d'ensemble du projet](Images/Pic-38.png) — capture à ajouter -->

---

## Étape 13 — Créer et distribuer des tenants

Une fois le cloud validé, créez un **projet** par tenant, un utilisateur avec le rôle `member` (jamais `admin`), des quotas, un réseau externe partagé pour les adresses flottantes, des flavors et des images.

> Guide pas à pas : [`Docs/Tenants.md`](Docs/Tenants.md)

---

## Référence — Fichiers importants

| Fichier | Emplacement | Description |
|---------|-------------|-------------|
| [`globals.yml`](Config/globals.yml) | `/etc/kolla/globals.yml` | Configuration principale du déploiement |
| [`multinode.hosts`](Config/multinode.hosts) | dépôt | Vos hôtes et rôles (sans les groupes dépendants de la version) |
| `multinode` | `~/multinode` | Inventaire complet, généré par [`Scripts/build-inventory.sh`](Scripts/build-inventory.sh) |
| [`build_swift_rings.sh`](Swift/build_swift_rings.sh) | — | Non utilisé : images Swift indisponibles en 2026.1 (voir [`Docs/Depannage.md`](Docs/Depannage.md)) |
| `passwords.yml` | `/etc/kolla/passwords.yml` | Mots de passe des services (généré par `kolla-genpwd`) |
| `admin-openrc.sh` | `/etc/kolla/admin-openrc.sh` | Variables d'environnement pour le client CLI |
| `clouds.yaml` | `/etc/kolla/clouds.yaml` | Configuration SDK OpenStack |
| Certificats TLS | `/etc/kolla/certificates/` | Certificats des API OpenStack |
| Certificats Octavia | `/etc/kolla/config/octavia/` | Certificats du load balancer (phase 2) |

---

## Documentation complémentaire

| Document | Contenu |
|----------|---------|
| [`Docs/Tenants.md`](Docs/Tenants.md) | Créer des projets, utilisateurs, quotas, réseaux, images et flavors pour vos tenants |
| [`Docs/HA-Roadmap.md`](Docs/HA-Roadmap.md) | État réel de la HA, topologie cible, tests de panne, sauvegardes |
| [`Docs/Corrections.md`](Docs/Corrections.md) | Corrections apportées à la configuration, avec leurs sources, et points restant à vérifier |
| [`Docs/Depannage.md`](Docs/Depannage.md) | Erreurs rencontrées pendant le déploiement et solutions |
