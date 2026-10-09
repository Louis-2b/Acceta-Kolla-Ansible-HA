# Passer en production — liste complète

Cette liste couvre ce qu'il faut décider, acheter, configurer, tester et organiser pour exploiter ce cloud en production, dans l'ordre. Cochez au fur et à mesure (`- [x]`).

> **Limites de ce document.** Les repères de dimensionnement sont des **ordres de grandeur usuels**, pas des valeurs de la documentation Kolla ni mesurées sur votre matériel. Les noms de variables Kolla-Ansible cités sont ceux connus pour la série 2026.1 ; vérifiez-les avec `grep -rn <variable> $VIRTUAL_ENV/share/kolla-ansible/ansible/` avant de les utiliser. Seules les étapes 1 à 11.3 du README ont été éprouvées sur le lab (jusqu'au `prechecks` réussi) : **le `deploy` n'a pas encore été exécuté**, et rien de ce qui suit (Ceph, OVN, registre privé, CA publique, sauvegardes) n'a été testé sur ce projet.

Sommaire : [0 Décisions](#0-décisions-à-prendre-avant-tout-achat) · [1 Dimensionnement](#1-matériel-et-dimensionnement) · [2 Réseau](#2-réseau) · [3 Serveurs](#3-préparation-des-serveurs-et-du-système) · [4 Déploiement](#4-poste-de-déploiement-git-et-secrets) · [5 Images](#5-images-conteneur-et-registre-privé) · [6 Ceph](#6-stockage--ceph) · [7 Neutron](#7-réseau-openstack-neutron) · [8 Calcul](#8-calcul-nova) · [9 globals.yml](#9-configuration-kolla-de-production) · [10 Identité](#10-identité-et-accès) · [11 Tenants](#11-modèle-de-tenants-et-offre) · [12 Sécurité](#12-sécurité) · [13 Supervision](#13-supervision-journaux-alertes) · [14 Sauvegardes](#14-sauvegardes-et-reprise-après-sinistre) · [15 Validation](#15-validation-avant-ouverture) · [16 Mise en production](#16-déploiement-de-production) · [17 Exploitation](#17-exploitation-courante) · [18 Organisation](#18-juridique-et-organisation) · [19 Plan](#19-plan-par-phases)

---

## 0. Décisions à prendre avant tout achat

Ces choix sont coûteux à inverser. Notez la réponse retenue et la raison.

| Décision | Options | Remarque |
|----------|---------|----------|
| Public visé | personnel / amis / clients payants | Détermine l'exigence de disponibilité, le juridique (§18), le support |
| Disponibilité visée | ex. 99 % / 99,9 % | Un 99,9 % ne tolère qu'environ 8 h 45 d'arrêt par an : impossible sans redondance électrique et réseau |
| Réseau virtuel | ML2/OVS ou **OVN** | À décider **avant** les données de tenants ; migrer ensuite est un chantier à part |
| Stockage | **Ceph** (recommandé pour une vraie HA) ou LVM/NFS (points uniques) | Ceph demande ≥ 3 nœuds de stockage dédiés |
| Origine des images | `kolla-build` + registre privé | Les images de quay.io sont « pour les tests » |
| Certificats | CA publique ou CA interne gérée | La CA de test oblige chaque client à importer `root.crt` |
| Nom de domaine et DNS | nom public ou interne | `openstack.tubie.lan` n'existe que chez vous |
| Où se trouve le cloud | local, colocation, hébergeur | Électricité, climatisation, accès Internet, adresses IP publiques |
| Budget et amortissement | | Prévoir le renouvellement du matériel (3 à 5 ans) |

- [ ] Tableau ci-dessus rempli et relu

---

## 1. Matériel et dimensionnement

### 1.1 Nombre de nœuds (minimum raisonnable pour une vraie HA)

| Rôle | Nombre | Pourquoi |
|------|:------:|----------|
| Contrôleurs | 3 | quorum Galera, RabbitMQ, Keepalived |
| Réseau | 2 (ou nœuds de passerelle OVN : 2 à 3) | éviter le point unique du routage et du NAT |
| Calcul | 3 ou plus | maintenance sans arrêt de service, marge pour évacuer un nœud en panne |
| Stockage Ceph | 3 minimum, idéalement 4 ou plus | 3 réplicas par défaut ; avec 3 nœuds exactement, une panne laisse le cluster dégradé sans capacité de récupération |
| Poste de déploiement | 1, **séparé des contrôleurs** | en lab c'est `controller01` ; en production, perdre un contrôleur ne doit pas faire perdre l'outil de déploiement |
| Registre d'images | 1 (ou 2) | peut être une petite VM hors du cloud |

Les contrôleurs peuvent aussi héberger les nœuds réseau à petite échelle, mais séparer les rôles réduit les pannes en cascade.

### 1.2 Repères de ressources (estimations à valider)

| Rôle | CPU | RAM | Disques |
|------|-----|-----|---------|
| Contrôleur | 8 à 16 cœurs | 32 à 64 Go | 2 × SSD en RAID 1 (système), SSD/NVMe rapide pour `/var/lib/docker` et MariaDB |
| Réseau | 8 cœurs | 16 à 32 Go | 2 × SSD en RAID 1 |
| Calcul | selon les VMs à héberger | RAM des VMs + 10 à 15 % pour l'hôte | 2 × SSD en RAID 1 (système) ; les disques des VMs sont sur Ceph |
| Ceph OSD | environ 1 cœur par OSD | environ 4 à 5 Go de RAM par OSD (valeur par défaut d'Ceph : 4 Gio, à vérifier dans votre version) | disques de données (SSD/NVMe pour de bonnes performances, HDD pour la capacité) + SSD/NVMe pour les journaux |

Capacité Ceph utilisable : environ le **tiers** de la capacité brute avec 3 réplicas, et ne jamais dépasser environ 80 % d'occupation.

### 1.3 Matériel

- [ ] Serveurs avec mémoire **ECC**
- [ ] Alimentations redondantes, chacune sur un circuit/une PDU distinct
- [ ] **Onduleur** (UPS) dimensionné, avec arrêt propre automatique des serveurs
- [ ] Climatisation/ventilation suffisante, surveillance de la température
- [ ] Carte d'administration à distance (iDRAC, iLO, IPMI) sur un réseau isolé
- [ ] Deux commutateurs (switchs) pour la redondance, liaisons agrégées (LACP/MLAG)
- [ ] Pièces de rechange (disques, alimentation, barrettes) ou contrat de garantie/remplacement
- [ ] Inventaire : numéros de série, emplacement, câblage étiqueté

---

## 2. Réseau

### 2.1 Séparation des réseaux (VLAN)

| Réseau | Usage | Remarque |
|--------|-------|----------|
| Administration (gestion) | SSH, Ansible | jamais exposé à Internet |
| API interne | communication entre services OpenStack | peut être le même que la gestion en petit déploiement |
| Tunnels des tenants | trafic VXLAN/Geneve entre nœuds | sa MTU doit couvrir l'encapsulation (environ +50 octets) |
| Stockage (public Ceph) | accès des clients aux données | idéalement MTU 9000 |
| Stockage (cluster Ceph) | réplication entre OSD | séparé du précédent, 10 GbE minimum recommandé |
| Externe (fournisseur) | adresses flottantes et VIP | seul réseau accessible depuis l'extérieur |
| BMC/IPMI | administration matérielle | isolé et filtré |

- [ ] Plan d'adressage documenté (une feuille par réseau, avec les plages réservées)
- [ ] Une adresse VIP libre par réseau concerné
- [ ] Plage d'adresses flottantes **dimensionnée** (un `/24` dédié, pas un `/28`)
- [ ] MTU décidée et appliquée de bout en bout (hôtes, commutateurs, Neutron)
- [ ] Agrégation de liens (bonding LACP) sur chaque nœud, sur deux commutateurs
- [ ] Débit : 10 GbE minimum pour le stockage, 25 GbE si beaucoup de VMs
- [ ] Au moins deux liaisons Internet si la disponibilité l'exige, avec routage/BGP si nécessaire
- [ ] IPv6 : décision prise (activé ou non)

### 2.2 Services d'infrastructure

- [ ] **DNS** : enregistrement `A` du FQDN vers la VIP, enregistrements pour chaque nœud, résolution inverse
- [ ] **NTP** : au moins 3 sources fiables, `chrony` sur tous les nœuds ; Galera, Ceph et les certificats sont sensibles à la dérive d'horloge
- [ ] Pare-feu périphérique : seuls les ports API nécessaires (`443` et ceux des services exposés) vers la VIP
- [ ] Résolution et accès sortant pour les mises à jour (ou miroir interne)
- [ ] Mesure de base : `iperf3` entre nœuds, latence, perte de paquets, noté avant le déploiement

---

## 3. Préparation des serveurs et du système

- [ ] BIOS/UEFI à jour, **virtualisation matérielle activée** (VT-x/AMD-V, VT-d/IOMMU), mode UEFI cohérent
- [ ] Firmware (BIOS, carte RAID, cartes réseau, disques) à jour et homogène
- [ ] RAID matériel ou logiciel pour les disques système ; **HBA en mode direct** (pas de RAID) pour les disques Ceph
- [ ] Installation de **Rocky Linux 10.x minimal**, la même version mineure partout
- [ ] Partitionnement : `/var/lib/docker` sur un volume séparé, avec marge ; `/var/log` séparé
- [ ] SELinux en mode `enforcing` ; ne pas le désactiver pour « faire passer » un déploiement
- [ ] Utilisateur d'exploitation (par exemple `kolla`) avec `sudo` sans mot de passe **limité à ce qui est nécessaire**, clés SSH uniquement, connexion `root` par SSH désactivée
- [ ] `/etc/hosts` ou DNS cohérent sur tous les nœuds
- [ ] `chrony` actif et synchronisé (`chronyc tracking`)
- [ ] Swap décidé (souvent faible ou désactivé sur les nœuds de calcul)
- [ ] Journal systémique persistant (`Storage=persistent` dans `journald`)
- [ ] Mises à jour du système appliquées avant le déploiement, puis **gelées** (même état sur tous les nœuds)
- [ ] Disques Ceph : vierges, sans partition, identifiés par numéro de série
- [ ] Contrôle uniforme : mêmes versions de noyau, même CPU/flags (important pour la migration à chaud, §8)

---

## 4. Poste de déploiement, Git et secrets

- [ ] Poste de déploiement **dédié** (pas un contrôleur), sauvegardé
- [ ] Environnement virtuel Python avec versions **figées** (`kolla-ansible` 2026.1, `ansible-core` 2.19 à 2.20), `requirements.txt` généré (`pip freeze`)
- [ ] Dépôt Git **privé** pour la configuration de production (`globals.yml`, inventaire, scripts) ; ce dépôt public ne doit contenir aucun secret
- [ ] **`passwords.yml` chiffré** (Ansible Vault) et stocké hors du dépôt ; vérifier dans `kolla-ansible --help` l'option du fichier de mot de passe Vault
- [ ] Gestionnaire de mots de passe ou coffre-fort pour le mot de passe `admin`, la phrase de passe de la CA, les clés Ceph
- [ ] Copie hors site et hors ligne de : `passwords.yml`, `globals.yml`, `/etc/kolla/certificates/`, clés Ceph (`ceph.client.*.keyring`)
- [ ] Revue des changements : toute modification de configuration passe par une demande de fusion (pull request) relue par une seconde personne si possible
- [ ] Journal des changements (qui, quoi, quand, pourquoi)

---

## 5. Images conteneur et registre privé

Les images de `quay.io/openstack.kolla` sont publiées « pour les tests » (d'où `--use-test-images`).

- [ ] Hôte de construction dédié, avec Docker et espace disque suffisant
- [ ] Construction avec `kolla-build` pour la série **2026.1** et la distribution **Rocky 10**, avec `kolla-build.conf` versionné dans Git
- [ ] Registre privé (par exemple le registre Docker de base ou Harbor), **en HTTPS** avec un certificat de confiance, authentifié
- [ ] `docker_registry`, `docker_namespace` et éventuellement `docker_registry_insecure` (à éviter) renseignés dans `globals.yml`
- [ ] Étiquette (`openstack_tag`) **figée** à une version construite, pas une étiquette mobile
- [ ] Analyse de vulnérabilités des images avant mise en service (Trivy ou équivalent) et procédure de reconstruction mensuelle
- [ ] Sauvegarde du registre (ou capacité de reconstruire les images à l'identique)
- [ ] Retrait de `--use-test-images` de toutes les commandes
- [ ] Essai complet : `kolla-ansible pull` depuis le registre privé sur les 6 types de nœuds

---

## 6. Stockage : Ceph

Objectif : supprimer le NFS de Glance, le LVM de Cinder et les points uniques associés.

- [ ] Cluster Ceph déployé **à part** d'OpenStack (par exemple avec `cephadm`), au moins 3 nœuds, 3 moniteurs (MON), 2 gestionnaires (MGR)
- [ ] Domaine de défaillance = **hôte** (CRUSH), jamais le disque
- [ ] Réseaux Ceph public et cluster séparés
- [ ] Pools créés avec réplication 3 et autoscaling des PG : `images` (Glance), `volumes` (Cinder), `vms` (Nova, si éphémère sur RBD), `backups` (Cinder Backup)
- [ ] Utilisateurs Ceph dédiés par service avec droits minimaux (`client.glance`, `client.cinder`, `client.cinder-backup`, `client.nova`) et leurs trousseaux de clés
- [ ] Fichiers `ceph.conf` et trousseaux placés dans `/etc/kolla/config/<service>/` selon la documentation Kolla
- [ ] Variables à définir dans `globals.yml` (à vérifier dans la doc 2026.1) : `glance_backend_ceph`, `cinder_backend_ceph`, `nova_backend_ceph`, `ceph_cinder_*`/`ceph_glance_*`, `enable_cinder_backup`, `cinder_backup_driver: "ceph"`
- [ ] **Retirer** : `glance_file_datadir_volume` (NFS), `enable_cinder_backend_lvm`, `cinder_cluster_skip_precheck` ; définir `cinder_cluster_name` si plusieurs `cinder-volume`
- [ ] Alertes Ceph : OSD arrêté, pool plein, horloge, dégradation, scrub en retard
- [ ] Seuils d'occupation (`nearfull`, `full`) connus et surveillés
- [ ] **Sauvegardes** : Ceph n'est pas une sauvegarde. Prévoir une copie des volumes (second cluster Ceph, S3 ou autre) via Cinder Backup, avec des tests de restauration
- [ ] Tests de panne : arrêt d'un nœud OSD, arrêt d'un MON, remplacement d'un disque

---

## 7. Réseau OpenStack (Neutron)

- [ ] **Choix OVS ou OVN** arrêté et documenté
- [ ] Si OVN : nœuds de passerelle (au moins 2), `neutron_plugin_agent: "ovn"` (à vérifier), tests de bascule
- [ ] Si OVS : au moins 2 nœuds dans `[network]`, `enable_neutron_agent_ha: "yes"` ; tester la bascule des routeurs
- [ ] Réseau externe fournisseur créé avec la bonne passerelle et un pool réellement libre
- [ ] MTU des réseaux de tenants cohérente avec l'encapsulation
- [ ] DNS pour les tenants : Designate ou résolveurs fournis dans les sous-réseaux
- [ ] Groupes de sécurité par défaut revus (refuser tout entrant par défaut)
- [ ] Quotas réseau par projet (réseaux, routeurs, adresses flottantes)
- [ ] Limite anti-usurpation : protection contre ARP/IP spoofing laissée active (valeur par défaut)
- [ ] Test : un tenant, un routeur, une adresse flottante, joignable depuis l'extérieur

---

## 8. Calcul (Nova)

- [ ] Virtualisation matérielle confirmée (`kvm`, pas `qemu`)
- [ ] `cpu_mode` choisi : `host-passthrough` (meilleures performances, impose des CPU identiques) ou un modèle commun (migration possible entre CPU différents)
- [ ] Ratios de sur-allocation décidés (CPU, RAM) et `reserved_host_memory_mb` réservé pour l'hôte
- [ ] Migration à chaud testée entre nœuds de calcul (stockage partagé Ceph)
- [ ] Zones de disponibilité ou agrégats d'hôtes si plusieurs baies/pièces
- [ ] Procédure d'évacuation d'un nœud en panne (`nova evacuate`) testée
- [ ] Optionnel : Masakari pour la reprise automatique des VMs (service existant dans Kolla ; à évaluer)
- [ ] Types d'instances (flavors) définis ; pas de flavor plus gros que le plus petit nœud
- [ ] Surveillance : ressources libres par nœud, VMs en erreur

---

## 9. Configuration Kolla de production

À reprendre dans le dépôt de production :

- [ ] `openstack_release: "2026.1"` et étiquette figée
- [ ] `docker_registry` / `docker_namespace` vers le registre privé
- [ ] VIP interne et externe, FQDN public, `network_interface`, `neutron_external_interface`, éventuellement `api_interface`, `storage_interface`, `tunnel_interface` séparées
- [ ] `enable_haproxy` et `enable_keepalived` ; `keepalived_virtual_router_id` unique sur le réseau
- [ ] TLS : certificats d'une CA de confiance (`kolla_externally_managed_cert` ou `kolla_copy_ca_into_containers` selon le cas), TLS interne **et** externe ; envisager `kolla_enable_tls_backend: "yes"`
- [ ] Services : n'activer que ce que vous exploiterez réellement (chaque service ajoute de la maintenance)
- [ ] Journalisation centralisée (`enable_central_logging`) et supervision activées (§13)
- [ ] Sauvegarde MariaDB (`enable_mariabackup`, à vérifier) et planification
- [ ] `nova_compute_virt_type: "kvm"`
- [ ] Retrait des contournements du lab : `cinder_cluster_skip_precheck`, `--use-test-images`, NFS Glance
- [ ] `kolla-ansible prechecks` sans aucune erreur ni contournement
- [ ] Revue ligne à ligne de `globals.yml` par une seconde personne

---

## 10. Identité et accès

- [ ] Compte `admin` : mot de passe long, jamais partagé, utilisé uniquement pour l'administration ; comptes administrateurs nominatifs distincts
- [ ] Rôle `member` pour les utilisateurs, `reader` pour la lecture seule, jamais `admin`
- [ ] Domaines Keystone : un par organisation si vous déléguez la gestion des utilisateurs
- [ ] Politique de mots de passe (`security_compliance` de Keystone), verrouillage après échecs
- [ ] Authentification multi-facteurs (TOTP) pour les administrateurs, si possible
- [ ] Option : fédération (LDAP, SSO) si vous avez un annuaire
- [ ] Durée de vie des jetons revue
- [ ] Comptes de service : mots de passe aléatoires générés par Kolla, jamais réutilisés
- [ ] Rotation prévue des mots de passe sensibles (procédure testée)
- [ ] Journal d'audit des actions d'administration conservé (journalisation Keystone/API)

---

## 11. Modèle de tenants et offre

- [ ] Un projet par client/équipe, un nom normalisé
- [ ] **Quotas systématiques** : instances, vCPU, RAM, volumes, Go, snapshots, réseaux, routeurs, adresses flottantes, groupes de sécurité
- [ ] Catalogue d'images publiques maintenues (mises à jour de sécurité) ; politique pour les images privées
- [ ] Flavors standard documentés
- [ ] Réseaux : seul le réseau externe est partagé
- [ ] Procédure d'intégration : création du projet, de l'utilisateur, des quotas, remise des identifiants par un canal sûr, remise de la CA si nécessaire, `clouds.yaml` d'exemple
- [ ] Procédure de départ : suppression des ressources, désactivation des comptes
- [ ] Limitation du débit des API (HAProxy) pour éviter qu'un tenant sature le plan de contrôle
- [ ] Facturation ou rétrofacturation éventuelle (CloudKitty) ou suivi d'usage
- [ ] Documentation utilisateur : démarrage rapide, limites, contacts, ce qui est sauvegardé ou non
- [ ] Canal de support et horaires annoncés

---

## 12. Sécurité

- [ ] Réseau d'administration inaccessible depuis Internet ; accès par VPN avec authentification forte
- [ ] Seuls les ports nécessaires exposés sur la VIP externe ; filtrage des autres
- [ ] SSH : clés uniquement, pas de `root`, `AllowUsers`, tentatives limitées
- [ ] SELinux `enforcing`, `auditd` actif, journaux envoyés hors des nœuds
- [ ] Pare-feu hôte (`firewalld`) : vérifier la compatibilité avec Kolla-Ansible 2026.1 avant de l'activer (à contrôler dans la doc)
- [ ] TLS partout où possible (externe, interne, backend)
- [ ] BMC/IPMI : mots de passe changés, firmware à jour, réseau isolé
- [ ] Docker : accès au socket limité aux administrateurs
- [ ] Images analysées, correctifs de sécurité suivis (listes de diffusion OpenStack et Rocky)
- [ ] Séparation des tâches : qui peut déployer, qui peut accéder aux sauvegardes
- [ ] Protection physique du matériel (accès contrôlé, caméra, inventaire)
- [ ] Test d'intrusion ou au minimum un scan (par exemple `testssl.sh` sur la VIP, `nmap` depuis l'extérieur)
- [ ] Plan de réponse à incident : qui prévenir, comment isoler un tenant, comment révoquer des accès
- [ ] Politique d'usage acceptable pour les tenants (spam, scans, minage, contenus illégaux) et procédure d'abus (§18)

---

## 13. Supervision, journaux, alertes

- [ ] Prometheus + Alertmanager + Grafana (`enable_prometheus`, `enable_grafana`) sur plusieurs nœuds si possible
- [ ] Journalisation centralisée (OpenSearch via `enable_central_logging`, à vérifier) avec rétention définie
- [ ] Alertes minimales :
  - nœud injoignable, disque > 80 %, RAM/CPU saturés
  - VIP non portée, `wsrep_cluster_size` < 3, file RabbitMQ qui grossit, partitions de réseau
  - `nova-compute`, `neutron-agent`, `cinder-volume` en `down`
  - Ceph : OSD arrêté, santé ≠ `HEALTH_OK`, pool presque plein
  - expiration des certificats (à 30 jours)
  - échec des sauvegardes
- [ ] Notification fiable (courriel, messagerie, SMS) et une astreinte définie
- [ ] **Supervision externe** (hors du cloud) pour savoir quand le cloud entier est tombé
- [ ] Page d'état pour les utilisateurs (optionnel)
- [ ] Tableaux de bord : capacité (CPU, RAM, stockage), tendance, croissance

---

## 14. Sauvegardes et reprise après sinistre

| À sauvegarder | Comment | Où |
|---------------|---------|-----|
| Bases de données OpenStack (MariaDB) | `kolla-ansible mariadb_backup` planifié | hors site |
| `/etc/kolla` (`passwords.yml`, `globals.yml`, certificats) | copie chiffrée | hors site, hors ligne |
| Dépôt de configuration | Git distant | autre hébergeur |
| Configuration et clés Ceph | export des trousseaux | hors site |
| Volumes des tenants | Cinder Backup vers un autre support (§6) | autre baie ou S3 |
| Images Glance importantes | copie des images | hors site |
| Registre d'images | sauvegarde ou reconstruction | |

- [ ] RPO (perte de données acceptable) et RTO (durée d'indisponibilité acceptable) définis par écrit
- [ ] Sauvegardes **automatisées**, chiffrées, avec rétention
- [ ] **Restauration testée** (une sauvegarde jamais restaurée n'est pas une sauvegarde) : base MariaDB sur un cluster d'essai, un volume, un contrôleur entier
- [ ] Procédure de reprise complète rédigée : perte d'un contrôleur, de deux (récupération Galera, `kolla-ansible mariadb_recovery`), de tout le site
- [ ] Procédure de **démarrage à froid** après coupure électrique générale (ordre : stockage, contrôleurs, réseau, calcul)
- [ ] Un test de reprise après sinistre au moins une fois par an

---

## 15. Validation avant ouverture

À réaliser sur le matériel de production **avant** d'accueillir des utilisateurs, ou sur une plate-forme de préproduction identique en plus petit (le lab actuel peut servir à répéter les mises à jour et les procédures).

- [ ] `prechecks` sans erreur, `deploy` terminé, `kolla-ansible post-deploy`
- [ ] `openstack service list`, `openstack compute service list`, `openstack network agent list`, `openstack volume service list`, `openstack hypervisor list` : tout `up`
- [ ] Cycle complet pour un tenant de test (réseau, routeur, VM, volume, adresse flottante, snapshot, suppression)
- [ ] Tests de panne, un seul composant à la fois, jamais deux contrôleurs sur trois :
  - arrêt du contrôleur qui porte la VIP
  - arrêt d'un nœud Galera, puis retour (`wsrep_cluster_size` = 3)
  - arrêt d'un nœud RabbitMQ
  - arrêt du nœud réseau actif / d'une passerelle OVN
  - arrêt d'un nœud de calcul avec évacuation des VMs
  - arrêt d'un nœud Ceph et d'un disque OSD
  - coupure d'un commutateur / d'un lien Internet
  - coupure électrique complète puis démarrage à froid
- [ ] Performance : `fio` (disque), `iperf3` (réseau), charge sur les API (par exemple Rally), mesures conservées comme référence
- [ ] Tests de conformité : Tempest (jeu de tests officiel) sur les services déployés
- [ ] Scan de sécurité externe (§12)
- [ ] Restauration d'une sauvegarde (§14)
- [ ] Essai de mise à jour sur la préproduction
- [ ] Documentation d'exploitation relue par quelqu'un qui n'a pas construit le cloud

---

## 16. Déploiement de production

Déroulé type, à adapter. Fenêtre de maintenance annoncée, sauvegarde de `/etc/kolla` avant chaque étape majeure.

1. [ ] Matériel monté, câblé, réseau validé (§2), serveurs préparés (§3)
2. [ ] Ceph déployé et validé (§6), pools et utilisateurs créés
3. [ ] Registre privé opérationnel avec les images (§5)
4. [ ] Poste de déploiement, Git, secrets prêts (§4)
5. [ ] `kolla-genpwd` puis chiffrement de `passwords.yml`
6. [ ] `kolla-ansible certificates` **ou** installation des certificats de la CA de confiance
7. [ ] `kolla-ansible bootstrap-servers -i multinode`
8. [ ] `kolla-ansible pull -i multinode`
9. [ ] `kolla-ansible prechecks -i multinode`
10. [ ] `kolla-ansible deploy -i multinode` (dans `tmux`)
11. [ ] `kolla-ansible post-deploy -i multinode`, puis `/etc/kolla/admin-openrc.sh`
12. [ ] Validations du §15
13. [ ] Création du réseau externe, des flavors, des images publiques (`Docs/Tenants.md`)
14. [ ] Supervision et alertes actives (§13), sauvegardes planifiées (§14)
15. [ ] Premier tenant pilote, puis ouverture progressive

---

## 17. Exploitation courante

- [ ] **Mises à jour du système** : un nœud à la fois, contrôleurs jamais en même temps, nœuds de calcul vidés d'abord (migration à chaud)
- [ ] **Mises à jour d'OpenStack** : lire les notes de version, sauvegarder, répéter en préproduction, puis `kolla-ansible upgrade`. Séries SLURP : 2026.1 vers 2027.1 sans passer par une version intermédiaire
- [ ] Renouvellement des certificats avant expiration, avec alerte
- [ ] Rotation des mots de passe selon la politique
- [ ] Suivi de la capacité (CPU, RAM, stockage, adresses IP) et commande du matériel à l'avance
- [ ] Nettoyage régulier : images Docker inutilisées, volumes orphelins, anciennes sauvegardes
- [ ] Ajout/retrait de nœuds : procédure écrite (`kolla-ansible deploy --limit`, `kolla-ansible stop` pour un retrait)
- [ ] Surveillance du support matériel (disques SMART, garanties)
- [ ] Revue mensuelle des alertes, des incidents et des quotas
- [ ] Exercices de reprise (§14)
- [ ] Documentation tenue à jour (schéma réseau, inventaire, procédures, contacts)

---

## 18. Juridique et organisation

À adapter à votre situation (particulier, association, entreprise) ; je ne suis pas juriste, faites-le valider.

- [ ] Statut juridique de l'activité si des tiers paient
- [ ] **Conditions générales** et politique d'usage acceptable
- [ ] Engagement de niveau de service (SLA) cohérent avec ce que l'infrastructure permet réellement
- [ ] Protection des données (RGPD si des données de personnes situées dans l'UE sont hébergées) : localisation des données, journaux, durée de conservation, procédure en cas de fuite
- [ ] Procédure de réponse aux demandes des autorités et aux signalements d'abus
- [ ] Assurance adaptée
- [ ] Contrats : fournisseur d'accès, colocation, maintenance matérielle
- [ ] Adresses IP publiques et, si besoin, blocs propres (RIPE) ; gestion des enregistrements DNS inverses
- [ ] Nom de domaine renouvelé, comptes d'administration du registrar protégés
- [ ] Modèle de coûts : matériel, énergie, Internet, licences, temps d'exploitation ; tarification si applicable
- [ ] Personnes : qui est d'astreinte, qui est remplaçant, accès aux secrets en cas d'indisponibilité (« facteur camion »)

---

## 19. Plan par phases

| Phase | Contenu | Sortie attendue |
|-------|---------|-----------------|
| A. Lab | Finir le `deploy` du lab, tenant d'essai, tests de panne du plan de contrôle | Procédure validée |
| B. Décisions et achats | §0 à §2 | Cahier des charges, commande |
| C. Plateforme | §3, §4, §5, réseau monté | Serveurs prêts, registre d'images |
| D. Stockage | §6 | Ceph sain, pools prêts |
| E. Déploiement | §7 à §9, §16 | Cloud déployé |
| F. Exploitation prête | §10 à §14 | Supervision, sauvegardes, procédures |
| G. Validation | §15 | Rapport de tests de panne et de performance |
| H. Ouverture | §11, §18 | Tenant pilote, puis ouverture progressive |

Vous pouvez en parallèle de la phase A poursuivre les phases B et C sur papier. Une fois la liste de matériel connue, adaptez `Config/multinode.hosts` et `Config/globals.yml` (second nœud réseau, calcul supplémentaire, Ceph, interfaces séparées).
