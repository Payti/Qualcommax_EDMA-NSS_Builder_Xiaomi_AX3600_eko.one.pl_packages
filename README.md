# Qualcommax EDMA-NSS Builder

### OpenWrt image builder for the Xiaomi AX3600 — NSS hardware offload on the upstream EDMA drivers

[![Build](https://img.shields.io/github/actions/workflow/status/JuliusBairaktaris/Qualcommax_NSS_Builder/build.yml?branch=main&style=flat-square&logo=github&label=Build)](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder/actions/workflows/build.yml)
[![Lint](https://img.shields.io/github/actions/workflow/status/JuliusBairaktaris/Qualcommax_NSS_Builder/lint.yml?branch=main&style=flat-square&logo=github&label=Lint)](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder/actions/workflows/lint.yml)
[![License](https://img.shields.io/github/license/JuliusBairaktaris/Qualcommax_NSS_Builder?style=flat-square&label=License)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/JuliusBairaktaris/Qualcommax_NSS_Builder?style=flat-square&label=Last%20Commit)](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder/commits/main)

A GitHub Actions pipeline that builds one OpenWrt image for the **Xiaomi
AX3600**: Qualcomm NSS hardware offload running on OpenWrt main's **upstream
`qca_edma` / `qca_ppe` ethernet drivers**
([PR #22381](https://github.com/openwrt/openwrt/pull/22381)) — not the vendor
`qca-nss-dp` / `qca-ssdk` stack every other NSS build uses. Built from
[openwrt-nss-edma](https://github.com/JuliusBairaktaris/openwrt-nss-edma) and
[nss-packages](https://github.com/JuliusBairaktaris/nss-packages).

New to NSS offload? The wiki page
**[NSS Offload Explained](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki/NSS-Offload-Explained)**
covers the concept from the ground up. Architecture, runtime model and measured
results are in the
**[full wiki](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki)**.

---

## Use it

Grab the `*-sysupgrade.bin` from the newest `edma-nss*`
[release](https://github.com/Payti/Qualcommax_EDMA-NSS_Builder_Xiaomi_AX3600_eko.one.pl_packages/releases)
and flash it:

```sh
sysupgrade -n /tmp/edma-nss_12.5-openwrt-qualcommax-ipq807x-xiaomi_ax3600-squashfs-sysupgrade.bin
```
```sh
sysupgrade -n /tmp/edma-nss_11.4-openwrt-qualcommax-ipq807x-xiaomi_ax3600-squashfs-sysupgrade.bin
```

Or via LuCI: **System → Backup / Flash Firmware**, upload, uncheck "Keep
settings" for a first-time flash. Coming from stock Xiaomi firmware? Install
OpenWrt first via the [official guide](https://openwrt.org/toh/xiaomi/ax3600).

**Runtime model:** the image boots as a normal OpenWrt system on the plain host
stack (Wi-Fi in host mode; the NSS modules are loaded but inert). The `nss`
service (`/etc/init.d/nss`, runs `/usr/sbin/nss-up`) then arms the NSS data
plane, boots the firmware, moves the radios onto the wifili path and starts
ECM (and SQM, once you have configured it); its output lands in the system
log (`logread -e nss`). **Every boot 
starts on the stock host-only stack** before the service arms NSS, so a reboot is
always a safe way back — the universal recovery path.
To stay on the host stack permanently:
`uci set nss.general.enabled='0'; uci commit nss` (survives sysupgrade).

Check plane health any time with `nss-status` over ssh, or in LuCI under
**Status → NSS Offload**.

Wi-Fi is **enabled out of the box**: SSID `OpenWrt`, WPA2/WPA3 (`sae-mixed`),
password `openwrt-nss`. The password is public in this repo — **change it on
first login** (LuCI → Network → Wireless).

---

## What ships by default

The `edma-nss` image enables the full offload stack plus a hardened, batteries-
included desktop-router config:

| Area | What's on |
|---|---|
| **NSS data plane** | `kmod-qca-nss-drv` + the `kmod-qca-ppe-nss` glue |
| **Connection offload** | ECM (`kmod-qca-nss-ecm`), PPPoE manager (`kmod-qca-nss-drv-pppoe`) — IPv4 NAT, IPv6 routing, PPPoE-over-VLAN |
| **Bridge offload** | `kmod-qca-nss-drv-bridge-mgr` — wired LAN bridging in hardware |
| **Multicast** | `kmod-qca-mcs` — same-subnet multicast hardware-bridged to snooped members |
| **SQM** | NSS qdiscs (`-qdisc`/`-igs`) + `sqm-scripts-nss` (`nss-edma.qos`, DSCP fast lane both directions) + `luci-app-sqm`. Ships as a **disabled template**: set `download`/`upload` to ~90-95 % of your measured line rate and enable it (LuCI **Network → SQM** or `uci`) — there is no safe universal default rate |
| **QoS marking** | `nssqos` + `luci-app-nssqos` — DSCP marking & fast-lane prioritization rules (CLI `/etc/config/nssqos`, LuCI **Network → QoS Marking (NSS)**) + live per-flow viewer (**Status → NSS Connections**), effective on accelerated flows |
| **Wi-Fi** | ath11k NSS offload (wifili) on both radios (`CONFIG_ATH11K_NSS_SUPPORT`); enabled by default (SSID `OpenWrt`, WPA2/WPA3, password `openwrt-nss` — change it) |
| **Diagnostics** | `nss-status` CLI health report (now incl. fast-lane counters) + LuCI **Status → NSS Offload** page + per-station firmware Wi-Fi counters (`/sys/kernel/debug/ieee80211/phy*/netdev:*/stations/<mac>/nss_stats`: A-MSDU aggregation, MPDU retries) |
| **Firmware/profile** | `NSS.FW.12.5-210-HK.R`, MEDIUM memory profile (512 MB) |
| **Security** | OpenSSH only (post-quantum KEX, AEAD/ETM, RSA ≥ 3072), `PKG_*` hardening (ASLR/PIE, stack protector, FORTIFY_3, RELRO, seccomp), WAN DROP + BCP38, HTTPS redirect, OQS provider in OpenSSL |
| **Toolchain** | GCC 15 + Graphite, Binutils 2.46, Mold linker, LTO, `-mcpu=cortex-a53+crc+crypto`; ccache off |
| **Userland** | LuCI (SSL), `htop`, `iperf3`, `curl`, BBR |

Toolchain and package pins live in
[`devices/xiaomi_ax3600/config`](devices/xiaomi_ax3600/config).

## Enable the rest in your fork

These are build-verified and wired in code, but **off by default** because the
reference network does not use them. Add the package to
`devices/xiaomi_ax3600/config` and rebuild:

| Feature | Add to config | Notes |
|---|---|---|
| Routed L3 multicast (IPTV WAN→LAN) | `CONFIG_PACKAGE_igmpproxy=y` (or `smcroute`) | ECM offloads each kernel MFC entry to the PPE; needs a real WAN multicast source and a two-VIF topology. See [`docs/CUSTOMIZE.md`](docs/CUSTOMIZE.md). |
| MAP-T / 464XLAT | `CONFIG_PACKAGE_kmod-nat46=y` | nat46 headers + QCA MAP-T exports are staged in the tree. |
| VXLAN | `CONFIG_PACKAGE_kmod-vxlan=y` | fdb/age-update offload via kernel patch `0972`. |
| MACVLAN | `CONFIG_PACKAGE_kmod-macvlan=y` | ECM support via kernel patch `0962`. |
| GRE | `CONFIG_PACKAGE_kmod-gre=y` | ECM GRE support builds. |

Not available on this platform/firmware: IPsec (ESP) offload, TLS/DTLS, and
CoDel ECN marking. (Wi-Fi mesh offload works on an 11.4-firmware build —
`NSS_FIRMWARE_VERSION_11_4` + `ATH11K_NSS_MESH_SUPPORT`; only the default 12.5
firmware blocks it.) See the
[Limitations](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki/Limitations-and-Roadmap)
page.

---

## Measured results

AX3600 (IPQ8071A, 512 MB), `NSS.FW.12.5-210`, kernel 6.18 — details in the
[wiki](https://github.com/JuliusBairaktaris/openwrt-nss-edma/wiki):

| Metric | Host path | NSS offload |
|---|---|---|
| 311 Mbit/s PPPoE NAT | ~42 % of one core (softirq) | **~99.7 % CPU idle** |
| SQM at 285 Mbit ingress | CPU-bound | **258 Mbit goodput, ~99 % idle** |
| RTT under shaped load | bufferbloat | **16 ms avg vs 20 idle — flat** |
| Wi-Fi data path | mac80211/ath11k on the CPU | **wifili on the NSS cores** |

---

## NSS Support Matrix

| Feature   | IPQ807x | IPQ60xx | Feature         | IPQ807x | IPQ60xx |
| --------- | :-----: | :-----: | --------------- | :-----: | :-----: |
| TUNIPIP6  |   ✅    |   ✅    | RMNET           |  🟨<sup><a href="#fn1">1</a></sup>  |  ⛔<sup><a href="#fn2">2</a></sup>  |
| PPPOE     |   ✅    |   ✅    | MIRROR          |   ✅    |   ✅    |
| L2TPV2    |   ✅    |   ✅    | WIFI (AP/STA)   |   ✅    |   ✅    |
| BRIDGE    |   ✅    |   ✅    | WIFI (WDS)      |  🟨<sup><a href="#fn1">1</a></sup>  |  🟨<sup><a href="#fn1">1</a></sup>  |
| VLAN      |   ✅    |   ✅    | WIFI (MESH)     |  🟨<sup><a href="#fn1">1</a></sup>  |  🟨<sup><a href="#fn1">1</a></sup>  |
| MAP_T     |   ✅    |   ✅    | WIFI (AP VLAN)  |  ⚠️<sup><a href="#fn4">4</a></sup>  |  ⚠️<sup><a href="#fn4">4</a></sup>  |
| TUN6RD    |   ✅    |   ✅    | IPSEC           |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |
| GRE       |   ✅    |   ✅    | PVXLAN          |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |
| PPTP      |   ✅    |   ✅    | CLMAP           |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |
| IGS       |   ✅    |   ✅    | TLS             |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |
| VXLAN     |   ✅    |   ✅    | CAPWAP          |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |
| MATCH     |   ✅    |   ✅    | DTLS            |   ❌<sup><a href="#fn3">3</a></sup>  |   ❌<sup><a href="#fn3">3</a></sup>  |

<a id="fn1"></a><sup>1</sup> 🟨 Requires **NSS FW 11.4**  
<a id="fn2"></a><sup>2</sup> ⛔ Not available on platform  
<a id="fn3"></a><sup>3</sup> ❌ Not available in NSS FW (11.4–12.5)  
<a id="fn4"></a><sup>4</sup> ⚠️ Broken in ath11k driver  

> **Note on IPQ50xx:**  
> Although the IPQ50xx family has NSS offloading capabilities, its architecture is substantially different from IPQ807x/IPQ60xx and requires additional patching. Most of my NSS patches for IPQ50xx have been blind guesswork (I do not own any), and thus far unsuccessful. If anyone with one of these devices gets NSS working, feel free to open a PR.

---

## NSS offload support matrix

What the firmware data plane accelerates on this stack (whole IPQ807x family).
Legend: ✅ offloaded & validated · 🟨 supported in code, opt-in, not validated
here · ⬜ deliberately not carried (software path is used) · ❌ not available on
this platform/firmware.

| Feature | IPQ807x | Notes |
|---|:---:|---|
| IPv4 NAT / routing | ✅ | ECM, line rate, host ~idle |
| IPv6 routing | ✅ | ECM |
| PPPoE (incl. over 802.1Q VLAN) | ✅ | validated on a PPPoE/VLAN WAN |
| 802.1Q VLAN | ✅ | ECM VLAN-tagged flows |
| SQM shaper (nsstbl + nssfq_codel) | ✅ | `nss-edma.qos`; zero-bufferbloat verified |
| Ingress shaping (IGS / nssmirred) | ✅ | `act_nssmirred` → ifb |
| DSCP / mark classification | ✅ | ECM DSCP + mark classifiers |
| CoDel ECN marking | ❌ | the 12.5 firmware does not ECN-mark (verified at firmware level); 11.4 not verified |
| Wi-Fi AP (wifili) | ✅ | both radios (QCN5024 + QCN5054) |
| Wi-Fi STA | 🟨 | wifili path present; AP is what's validated |
| Wi-Fi WDS | 🟨 | not validated |
| Wi-Fi mesh | ✅¹ | offloaded with the NSS firmware 11.4 build option (`ATH11K_NSS_MESH_SUPPORT`); on the default 12.5 firmware mesh stays on the host path |
| Wi-Fi AP-VLAN | ❌ | broken in the ath11k driver |
| Bridge (wired LAN, same-subnet L2) | ✅ | `nss-bridge-mgr`; firmware hardware-bridges the wired ports (host idle). Wi-Fi members stay host-side until Wi-Fi offload |
| Inter-subnet routing (two subnets on one bridge) | ✅ | same-bridge hairpin route `lan1→lan2` accelerated (`accel_mode=2`, host flat), no config change |
| Multicast (same-subnet / bridged) | ✅ | `qca-mcs` snooping; PPE hardware-bridges to snooped members, host flat |
| Multicast (routed across subnets) | 🟨 | ECM `mc_create` path + kernel ipmr hooks built; needs a multicast-routing daemon (igmpproxy/smcroute) and a two-VIF topology |
| GRE | 🟨 | ECM support builds with `kmod-gre`; not in the default config |
| MAP-T / DS-Lite | 🟨 | needs `kmod-nat46` |
| 6RD / IPIP6 (SIT) | 🟨 | needs `kmod-sit` / `kmod-ip6-tunnel` |
| VXLAN | 🟨 | needs `kmod-vxlan` |
| OVS bridge | ⬜ | `nss-bridge-mgr` OVS path compiled out; would need `kmod-qca-ovsmgr` |
| MACVLAN | 🟨 | kernel patch carried; needs `kmod-macvlan` |
| L2TPv2 / PPTP | ⬜ | ECM interface off — those kernel hooks are not ported |
| Bonding / LAG | ⬜ | kernel bonding hooks not carried |
| IPsec (ESP) | ❌ | not viable on IPQ807x; `nss-crypto`/`cfi` not carried |
| TLS / DTLS / CAPWAP | ❌ | not supported (matches the vendor matrix) |

The opt-in rows are build-verified against this tree: selecting `kmod-nat46`,
`kmod-vxlan`, `kmod-macvlan`, `kmod-gre`, `kmod-sit` or `kmod-ip6-tunnel` turns
the matching ECM interface support on and links cleanly. Bonding/LAG and
L2TPv2/PPTP stay off by design — their QCA kernel hooks are not carried, and
the ECM package forces those interface types off so selecting the kmods cannot
break the build. `kmod-ipsec` also builds, but ESP flows stay on the host path
(no NSS crypto on this platform).

All IPQ807x-family boards carry the NSS device-tree nodes; per-board validation
reports are the open item.

### ¹ 802.11s mesh offload (firmware 11.4 build option)

Mesh offload is a firmware capability: NSS firmware 11.4.0.5 is the only
line that supports mesh interfaces — every newer published firmware
rejects them at the firmware level (verified on 12.5-210). Selecting
`ATH11K_NSS_MESH_SUPPORT` therefore requires `NSS_FIRMWARE_VERSION_11_4`
(same firmware tarball). Everything else works on 11.4 as on 12.5 —
NAT/routing, PPPoE/VLAN, wifili AP offload, bridge, multicast, and SQM
with the same `nss-edma.qos` script (the qdisc module selects the
firmware's statistics format at build time); all verified live on
11.4.0.5-6. On 12.5 images, mesh interfaces keep Wi-Fi on the host path
and everything wired stays offloaded.

---

## Build it yourself

Everything is parameterized in the `env:` block of
[`.github/workflows/build.yml`](.github/workflows/build.yml) — fork the repo,
edit, and the pipeline builds on push. Or build locally:

```sh
git clone --branch nss-edma-rework https://github.com/JuliusBairaktaris/openwrt-nss-edma openwrt
cd openwrt
cp feeds.conf.default feeds.conf
echo "src-git nss https://github.com/JuliusBairaktaris/nss-packages.git;edma-nss" >> feeds.conf
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../Qualcommax_NSS_Builder/devices/xiaomi_ax3600/config .config
make defconfig && make -j"$(nproc)"
```

The NSS runtime tools (`nss-up`, `nss-status`, the `nss` boot service, the
QoS marking CLI/UI) ship as regular packages from the openwrt fork
(`nss-tools`, `nssqos`, `luci-app-nss`, `luci-app-nssqos`) — plain fork
checkouts get them by selecting the packages, no builder needed. The few
remaining overlay files (the disabled SQM template, wireless defaults, SSH config)
are under `devices/xiaomi_ax3600/files*/` — copy them into the image with a
`files/` directory or the builder pipeline. See [`docs/CUSTOMIZE.md`](docs/CUSTOMIZE.md)
for the full customization guide and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for how the pipeline works.

### Repo layout

```
devices/xiaomi_ax3600/
  config                 # the .config (target, toolchain, hardening, NSS packages)
  files/                 # base rootfs overlay (sshd_config, QoL uci-defaults)
  files.edma-nss/        # edma-nss overlay (SQM template, rc.local)
patches/                 # directory to load custom firmware patches
screenshots/             # screenshots this working build
scripts/                 # check-updates, prepare-build, prune-releases (tested, linted)
docs/                    # CUSTOMIZE.md, ARCHITECTURE.md
.github/workflows/       # build.yml (check → build → prune), lint.yml
```

The pipeline runs `check → build → prune`: `check` resolves the upstream/NSS
ref to a SHA and skips a scheduled build when nothing changed; `build` applies
the config + overlays, compiles, and publishes a release; `prune` keeps the
newest `KEEP` releases. Builds are uncached (fresh runner, reproducible
`SOURCE_DATE_EPOCH`) and the pipeline is linted (`actionlint`, `shellcheck`,
`yamllint`) on every PR.

---

## Contributing

Issues and PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Acknowledgements

- **[JuliusBairaktaris](https://github.com/JuliusBairaktaris)** — the
  [openwrt-nss-edma](https://github.com/JuliusBairaktaris/openwrt-nss-edma) this stack builds on
- **[Ansuel (Christian Marangi)](https://github.com/Ansuel)** — the
  [EDMA rework](https://github.com/openwrt/openwrt/pull/22381) this stack builds on
- **[qosmio](https://github.com/qosmio)** — NSS development, the
  [openwrt-ipq](https://github.com/qosmio/openwrt-ipq) tree, and the Wi-Fi
  offload patch lineage
- **[rodriguezst](https://github.com/rodriguezst)** — original
  [ipq807x-openwrt-builder](https://github.com/rodriguezst/ipq807x-openwrt-builder)
- **OpenWrt community** — the
  [IPQ807x NSS Build thread](https://forum.openwrt.org/t/ipq807x-nss-build/148529)

## Support the project

This is an unpaid, single-maintainer effort. If this work is useful to you,
consider chipping in — it goes toward IPQ807x development and hardware to start
looking into **IPQ50xx** and **IPQ60xx** next.

- **[GitHub Sponsors](https://github.com/sponsors/JuliusBairaktaris)** — zero-fee, GitHub-native
- **[PayPal](https://paypal.me/JuliusBairaktaris)** — one-off donations

Thank you!

## License

[GPL-2.0](LICENSE), consistent with OpenWrt.
