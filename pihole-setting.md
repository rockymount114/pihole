# Pi-hole + Unbound on Raspberry Pi 5 - Complete Reference

> Location: `~/pihole` on `raspberrypi`  
> Status: **Healthy** - Fixed `TCP connection failed while receiving payload length` as of 2026-08-09  
> Stack: Pi-hole (filtering) + Unbound (recursive resolver) + Docker + Portainer  
> Image: `mvance/unbound-rpi:latest`

---

## 1. Directory Structure

```
/home/pi/pihole/  (or ~/pihole)
├── .env                      # Pi-hole web password
├── docker-compose.yml        # MAIN FILE
├── etc-pihole/               # Pi-hole persistent data
├── etc-dnsmasq.d/            # Custom dnsmasq configs (optional)
└── unbound/                  # ACTIVE unbound config - REQUIRED
    ├── unbound.conf          # Custom unbound config
    └── root.hints            # Root DNS servers list
```

## 2. File Contents (Copy-Paste Ready)

### 2.1 `docker-compose.yml` - FINAL FIXED FOR mvance/unbound-rpi

**Fixes:**
1. `CONNECTION_ERROR (172.26.0.3#53): TCP connection failed while receiving payload length from upstream`
2. Portainer `unhealthy` - `mvance` image also has no `/bin/sh`, must use `CMD` not `CMD-SHELL`
3. Adds volumes for custom unbound.conf - without this, mvance default blocks Docker subnet

```yaml
services:
  pihole:
    container_name: pihole
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
      FTLCONF_dns_replyWhenBusy: 'allow'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    depends_on:
      unbound:
        condition: service_healthy
    networks:
      pihole_net:
        ipv4_address: 172.26.0.2

  unbound:
    container_name: unbound
    image: mvance/unbound-rpi:latest
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

### 2.3 `unbound/unbound.conf` - FIXES TCP ERROR

The 2 lines that fix `TCP connection failed while receiving payload length`:

* `access-control: 172.26.0.0/24 allow` - allows Pi-hole to query
* `edns-buffer-size: 1232` + `edns-tcp-keepalive: yes` - fixes TCP close

```conf
server:
    verbosity: 1
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    # Access control - CRITICAL FOR DOCKER
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
    # For mvance image, root.key is auto-managed, but we keep file ref
    trust-anchor-file: "/opt/unbound/etc/unbound/root.key"
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
```

### 2.4 `unbound/root.hints`

Update every 6 months:

```bash
curl -o ~/pihole/unbound/root.hints https://www.internic.net/domain/named.cache
```

## 3. Installation & Management

### First time setup

```bash
cd ~/pihole
mkdir -p unbound
curl -o unbound/root.hints https://www.internic.net/domain/named.cache
# create unbound/unbound.conf from above
docker compose up -d
```

### Verify fix

```bash
# should show healthy, not unhealthy
docker inspect unbound --format='{{.State.Health.Status}}'

# should return IP via TCP
docker exec pihole dig @172.26.0.3 google.com +tcp +short

# should show NO errors
docker logs pihole --since 24h | grep "172.26.0.3#53" || echo "FIXED - no CONNECTION_ERROR"
docker logs unbound --tail 20
```

### Daily commands

```bash
docker ps
docker exec pihole pihole status
docker logs pihole --tail 100 -f
docker logs unbound --tail 100 -f

# update
curl -o ./unbound/root.hints https://www.internic.net/domain/named.cache
docker compose pull
docker compose up -d
```

## 4. Root Cause of Yesterday's Error

```
Connection error (172.26.0.3#53): TCP connection failed while receiving payload length from upstream (Connection prematurely closed by remote server)
```

**Cause:** `mvance/unbound-rpi:latest` without custom volume uses default config that:
1. Does not allow `172.26.0.0/24` - closes TCP from Pi-hole
2. Has default `edns-buffer-size: 4096` which causes fragmentation over Docker bridge

**Fix:** Mount custom `unbound.conf` with `access-control: 172.26.0.0/24 allow` and `edns-buffer-size: 1232`.

Also `mvance` is distroless like `klutchell` - healthcheck must be `["CMD", "drill", ...]` not `CMD-SHELL` or `/bin/sh` error.

## 5. Why Unbound?

| Pi-hole alone | Pi-hole + Unbound |
|---|---|
| Forwards to Cloudflare/Google, they log you | You query root servers directly, no logging |
| Trusts upstream | Validates DNSSEC yourself |
| Cloudflare can filter | True authoritative answer |
| Cache only in Pi-hole | Double cache, 0 msec for repeats |

## 6. Network Flow

```
Phone/PC -> Pi-hole 172.26.0.2:53 (blocks ads) -> Unbound 172.26.0.3:53 -> Root -> TLD -> Auth -> Internet
```

Dashboard: http://raspberrypi.local:8080/admin

## 7. Backup

```bash
cd ~
tar -czf pihole-backup-$(date +%F).tar.gz pihole/etc-pihole pihole/unbound pihole/docker-compose.yml pihole/.env
```
