# Pi-hole + Unbound on Raspberry Pi 5 - Complete Reference

> Location: `~/pihole` on `raspberrypi`  
> Status: **Healthy** as of 2026-08-09  
> Stack: Pi-hole (filtering) + Unbound (recursive resolver) + Docker + Portainer

---

## 1. Directory Structure

```
/home/root/pihole/  (or ~/pihole)
├── .env                      # Pi-hole web password
├── docker-compose.yml        # MAIN FILE - fixed healthy version
├── docker-compose.yml.bak    # backup
├── etc-pihole/               # Pi-hole persistent data
├── etc-dnsmasq.d/            # Custom dnsmasq configs (optional)
├── etc-unbound/              # OLD - not used anymore, can delete
└── unbound/                  # ACTIVE unbound config
    ├── unbound.conf          # Custom unbound config
    └── root.hints            # Root DNS servers list
```

## 2. File Contents (Copy-Paste Ready)

### 2.1 `docker-compose.yml` - FINAL FIXED VERSION
**Why this version?** Fixes `CONNECTION_ERROR (172.26.0.3#53)` and Portainer `unhealthy`.

Key fixes:
1. Mounts your custom `unbound.conf` and `root.hints`
2. Uses `CMD` not `CMD-SHELL` (klutchell image has no /bin/sh)
3. Uses `drill` for healthcheck (busybox image doesn't have dig +short)
4. `condition: service_started` to avoid 30s wait on boot

```yaml
services:
  pihole:
    container_name: pihole
    hostname: pihole
    image: pihole/pihole:latest
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"
      - "8443:443/tcp"
    environment:
      TZ: 'America/New_York'
      FTLCONF_webserver_api_password: ${MYPASSWORD}
      FTLCONF_webserver_domain: 'pihole.aibadminton.com'
      FTLCONF_dns_listeningMode: 'all'
      FTLCONF_dns_upstreams: '172.26.0.3#53'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    depends_on:
      unbound:
        condition: service_started
    networks:
      pihole_net:
        ipv4_address: 172.26.0.2

  unbound:
    container_name: unbound
    hostname: unbound
    image: klutchell/unbound:latest
    restart: unless-stopped
    volumes:
      - ./unbound/unbound.conf:/opt/unbound/etc/unbound/unbound.conf:ro
      - ./unbound/root.hints:/opt/unbound/etc/unbound/root.hints:ro
    networks:
      pihole_net:
        ipv4_address: 172.26.0.3
    healthcheck:
      test: ["CMD", "drill", "google.com", "@127.0.0.1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

networks:
  pihole_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.26.0.0/24
          gateway: 172.26.0.1
```

### 2.2 `.env`

```env
MYPASSWORD=YourSuperStrongPasswordHere
```

### 2.3 `unbound/unbound.conf`

```conf
server:
    verbosity: 1
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    # Access control - CRITICAL for Docker network
    access-control: 0.0.0.0/0 deny
    access-control: 127.0.0.0/8 allow
    access-control: 172.26.0.0/24 allow
    access-control: 10.0.0.0/8 allow
    access-control: 192.168.0.0/16 allow

    # Root hints
    root-hints: "/opt/unbound/etc/unbound/root.hints"

    # Security
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-below-nxdomain: yes
    use-caps-for-id: no

    # DNSSEC
    trust-anchor-file: "/etc/unbound/root.key"
    val-clean-additional: yes

    # Privacy
    qname-minimisation: yes
    minimal-responses: yes

    # Performance - FIX FOR CONNECTION_ERROR
    edns-buffer-size: 1232
    prefetch: yes
    prefetch-key: yes
    num-threads: 2
    msg-cache-size: 64m
    rrset-cache-size: 128m
    cache-min-ttl: 300
    cache-max-ttl: 86400
    serve-expired: yes
    serve-expired-ttl: 3600
    edns-tcp-keepalive: yes
    edns-tcp-keepalive-timeout: 10000
    tcp-idle-timeout: 30000

    # Logging
    log-queries: no
    log-replies: no
    log-servfail: yes

# Optional: enable for stats
# remote-control:
#     control-enable: yes
#     control-interface: 127.0.0.1

    # No forwarders - we are recursive!
```

### 2.4 `unbound/root.hints`
Download / update every 6 months:

```bash
curl -o ~/pihole/unbound/root.hints https://www.internic.net/domain/named.cache
```

## 3. Installation & Management Commands

### First time setup
```bash
cd ~/pihole
curl -o ./unbound/root.hints https://www.internic.net/domain/named.cache
docker compose up -d
```

### Daily commands
```bash
# status
docker ps
docker exec pihole pihole status
docker inspect unbound --format='{{.State.Health.Status}}'  # should be healthy

# logs
docker logs pihole --tail 100 -f
docker logs unbound --tail 100 -f

# check if CONNECTION_ERROR is gone
docker logs pihole --since 24h | grep CONNECTION_ERROR || echo "FIXED - no errors"

# test recursion
docker exec unbound drill google.com @127.0.0.1
docker exec pihole dig @172.26.0.3 google.com +tcp

# update root hints + images
curl -o ./unbound/root.hints https://www.internic.net/domain/named.cache
docker compose pull
docker compose up -d
```

### Fix Portainer unhealthy (history)
Error was: `OCI runtime exec failed: /bin/sh: no such file or directory`
Reason: `klutchell/unbound` is distroless, no shell. Must use `["CMD", "drill", ...]` not `CMD-SHELL`.

## 4. Why Unbound?

| Pi-hole alone | Pi-hole + Unbound (your setup) |
|---|---|
| Forwards to Cloudflare/Google, they log you | You query root servers directly, no logging |
| Trusts upstream answer | Validates DNSSEC yourself |
| Cloudflare can filter/censor | Get true authoritative answer |
| Cache only in Pi-hole | Double cache, 0 msec for repeat domains |

Trade-off: first query to new domain is ~100ms slower (full recursion). Prefetch fixes this.

## 5. Network Flow

```
Phone/PC (192.168.x.x)
  -> Pi-hole 172.26.0.2:53 (blocks ads)
    -> Unbound 172.26.0.3:53 (recursive)
      -> Root (.) -> TLD (.com) -> Authoritative (google.com)
  -> Internet
```

Pi-hole dashboard: http://raspberrypi.local:8080/admin

## 6. Backup

```bash
cd ~
tar -czf pihole-backup-$(date +%F).tar.gz pihole/etc-pihole pihole/unbound pihole/docker-compose.yml pihole/.env
```

## 7. Cleanup old folder

Your `etc-unbound/` is unused. After confirming new setup works for a week:

```bash
# rm -rf ~/pihole/etc-unbound/
```
