# Haute disponibilité — état réel et feuille de route

Objectif du projet : un cloud privé OpenStack hautement disponible, dont vous gardez le contrôle, avec des tenants isolés. Ce document dit **ce qui est réellement HA aujourd'hui**, ce qui ne l'est pas, et dans quel ordre y remédier.

## 1. État actuel de la topologie (6 nœuds)

| Composant | HA ? | Détail |
|-----------|:----:|--------|
| API OpenStack + VIP (HAProxy + Keepalived) | ✅ | 3 contrôleurs ; la VIP `172.20.10.14` bascule si le nœud qui la porte tombe |
| MariaDB (Galera) | ✅ | 3 nœuds ; tolère la perte d'un nœud (quorum 2/3) |
| RabbitMQ | ✅ | cluster sur les 3 contrôleurs |
| Réseau (Neutron : L3, DHCP, metadata) | ❌ | un seul nœud `network01` : s'il tombe, plus de routage, de NAT ni d'adresses flottantes |
| Calcul (Nova) | ❌ | un seul `compute01` : s'il tombe, toutes les VMs sont arrêtées |
| Stockage bloc (Cinder LVM) | ❌ | un seul `storage01` ; la documentation Kolla signale des problèmes du backend LVM en multi-contrôleurs |
| Stockage objet (Swift) | — | non déployé : images conteneur indisponibles pour 2026.1 |
| Images (Glance sur NFS) | ❌ | partage NFS servi par `storage01` : point de défaillance unique |
| Supervision | ❌ | Prometheus et Grafana uniquement sur `controller01` |
| Nœud de déploiement | ⚠️ | `controller01` : sans impact en production, mais perdre `/etc/kolla` (mots de passe, certificats) est grave |

Conclusion : seul le **plan de contrôle** est HA. Les VMs et leurs données dépendent de nœuds uniques.

**Dimensionnement actuel (mesuré le 08/10/2026).** Contrôleurs : 4 vCPU et 3,8 Go de RAM ; `network01`, `compute01` et `storage01` : 4 vCPU et 1,9 Go ; disque racine de 35 Go partout. C'est très en dessous de ce qu'un plan de contrôle OpenStack demande : il faut augmenter la RAM avant le déploiement (voir [`Depannage.md`](Depannage.md#ram-insuffisante)). Une fois le cluster stable, la RAM disponible sur `compute01` limitera aussi le nombre de VMs de tenants.

## 2. Topologie cible

Repères usuels (à ajuster à votre matériel) :

| Rôle | Minimum pour une vraie HA | Remarque |
|------|---------------------------|----------|
| Contrôleurs | 3 | déjà en place |
| Réseau | 2 | variable `enable_neutron_agent_ha` à activer avec ≥ 2 nœuds dans `[network]` |
| Calcul | 2 ou plus | permet de déplacer les VMs lors d'une maintenance |
| Stockage | 3 nœuds Ceph | Ceph est déployé **à part** (par exemple avec cephadm) ; Kolla-Ansible le consomme pour Glance, Cinder et Nova |
| Réseau physique | séparer gestion, stockage, tenants, externe | une seule carte réseau partagée est un goulot et un point de défaillance |

Avec Ceph, on peut supprimer le NFS de Glance, le LVM de Cinder et le backend `file` de Gnocchi, c'est-à-dire trois points uniques d'un coup.

## 3. Ordre recommandé

1. **Valider la phase 1** (README, étapes 1 à 12) et les tests de panne du paragraphe 4.
2. **Sauvegarder** `/etc/kolla` (en particulier `passwords.yml`, `globals.yml` et `certificates/`) hors des nœuds, et planifier des sauvegardes MariaDB (`kolla-ansible mariadb_backup -i ~/multinode`).
3. **Second nœud réseau** : ajoutez `network02` dans [`Config/multinode.hosts`](../Config/multinode.hosts), régénérez l'inventaire, puis activez `enable_neutron_agent_ha: "yes"` dans `globals.yml`.
4. **Second nœud de calcul** (`compute02`).
5. **Ceph externe**, puis bascule de Glance, Cinder et Nova dessus (`glance_backend_ceph`, etc.).
6. **Images de production** : les images de `quay.io/openstack.kolla` sont publiées « pour les tests » (d'où `--use-test-images`). Pour la production, construire ses images avec `kolla-build`, les stocker dans un registre privé et renseigner `docker_registry` / `docker_namespace` dans `globals.yml`. Flux non testé sur ce projet : à documenter et à valider à ce moment-là.
7. **Décider ML2/OVS ou OVN avant d'avoir des données de tenants** : OVN (`neutron_plugin_agent: "ovn"`) évite les agents L3/DHCP centralisés, mais migrer de l'un à l'autre sur un cloud en production est un chantier à part.
8. **Phase 2** : Octavia (image amphora, réseau de gestion), puis télémétrie (avec backend Gnocchi partagé).

## 4. Tests de panne (à faire avant d'accueillir des tenants)

Ne coupez jamais **deux** contrôleurs sur trois en même temps : le quorum Galera serait perdu.

```bash
# Quel contrôleur porte la VIP ?
for h in controller01 controller02 controller03; do
  echo -n "$h : "; ssh kolla@$h "ip -br a show ens160 | grep -c 172.20.10.14"
done

# Santé Galera (attendu : wsrep_cluster_size = 3)
docker exec mariadb mysql -uroot \
  -p"$(grep '^database_password:' /etc/kolla/passwords.yml | awk '{print $2}')" \
  -e "SHOW STATUS LIKE 'wsrep_cluster_size'"

# Santé RabbitMQ
docker exec rabbitmq rabbitmqctl cluster_status
```

(Ces commandes `docker exec` se lancent sur le contrôleur concerné.)

Scénario : éteignez le contrôleur qui porte la VIP (`sudo poweroff`). Vérifiez que :

- la VIP réapparaît sur un autre contrôleur en quelques secondes ;
- `openstack token issue` et `openstack server list` répondent encore ;
- après rallumage, `wsrep_cluster_size` repasse à 3.

## 5. Mises à jour et durée de vie des versions

| Série | Type | État (oct. 2026) |
|-------|------|------------------|
| 2024.2 Dalmatian | non SLURP | fin de vie le 29/04/2026 |
| 2025.1 Epoxy | SLURP | passage en « unmaintained » estimé au 02/10/2026 |
| 2025.2 Flamingo | non SLURP | maintenue, fin de vie estimée au 28/04/2027 |
| **2026.1 Gazpacho** | **SLURP** | **maintenue, « unmaintained » estimé au 27/10/2027 (série ciblée)** |
| 2027.1 Indri | SLURP | prévue vers le 24/03/2027 |

Les séries SLURP permettent de sauter d'une série SLURP à la suivante (2026.1 vers 2027.1) sans passer par la version intermédiaire : c'est le chemin de mise à jour le plus simple pour un petit cloud privé.

Source : [releases.openstack.org](https://releases.openstack.org/).
