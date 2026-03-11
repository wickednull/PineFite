# PineFite
PineFite — A wifite-style wireless auditor built for the WiFi Pineapple Pager. Scan for nearby networks, select your target, and launch WPA handshake capture, PMKID, WPS Pixie-Dust, or WPS PIN attacks — all from the Pager’s native UI. Loot saved to /root/loot/pinefite. For authorized use only.
# PineFite

**Author:** wickedNull  
**Version:** 1.0  
**Category:** Reconnaissance  
**Platform:** Hak5 WiFi Pineapple Pager

-----

## Description

PineFite is a wifite-style wireless auditor built natively for the WiFi Pineapple Pager. Scan for nearby networks, select your target, and launch attacks — all from the Pager’s built-in UI. No laptop required.

> For authorized penetration testing use only.

-----

## Attack Modes

|#|Mode          |Tools Required                       |Notes                       |
|-|--------------|-------------------------------------|----------------------------|
|1|WPA Handshake |airodump-ng, aireplay-ng, aircrack-ng|Deauth → capture → verify   |
|2|PMKID         |hcxdumptool, hcxpcapngtool           |Clientless, no deauth needed|
|3|WPS Pixie-Dust|reaver, pixiewps                     |Fast offline attack         |
|4|WPS PIN       |reaver                               |Online brute-force, slow    |

-----

## Requirements

### System

- Hak5 WiFi Pineapple Pager (firmware with DuckyScript support)
- Monitor mode interface (`wlan0mon` or `wlan1mon` — both present by default)

### Tools

The aircrack-ng suite must be installed on MMC:

```bash
opkg update
opkg install -d mmc aircrack-ng
```

Optional tools for additional attack modes:

```bash
opkg install -d mmc hcxdumptool hcxtools reaver
```

> Install to MMC (`-d mmc`) to avoid filling the 32MB overlay partition.

-----

## Installation

```bash
# On the Pager via SSH
mkdir -p /root/payloads/user/reconnaissance/pinefite

# From your machine
scp payload.sh root@172.16.52.1:/root/payloads/user/reconnaissance/pinefite/payload.sh
```

Or clone directly on the Pager:

```bash
cd /root/payloads/user/reconnaissance
git clone https://github.com/wickedNull/pinefite pinefite
```

-----

## Usage

1. Select **Payloads → Reconnaissance → PineFite** from the Pager dashboard
1. Choose your attack mode (1–4)
1. Wait for the 20-second scan to complete
1. Select your target network from the list
1. Confirm and launch

### Controls

|Button   |Action          |
|---------|----------------|
|UP / DOWN|Navigate menus  |
|GREEN (A)|Select / Confirm|
|RED (B)  |Back / Cancel   |

-----

## Loot

All captures and logs are saved to `/root/loot/pinefite/`:

```
/root/loot/pinefite/
├── pinefite.log          # Debug log
├── cracked.txt           # Cracked WPS credentials
├── <ESSID>_<date>.cap    # WPA handshake captures
├── <ESSID>_<date>.pcapng # PMKID captures
├── <ESSID>_<date>.22000  # PMKID hash (hashcat format)
└── reaver_<ESSID>.log    # WPS PIN brute-force log
```

### Cracking Handshakes Off-Device

WPA handshakes and PMKID hashes can be cracked on a more powerful machine:

```bash
# WPA handshake
aircrack-ng -w rockyou.txt capture.cap

# PMKID (hashcat)
hashcat -m 22000 capture.22000 rockyou.txt
```

-----

## Troubleshooting

|Problem                    |Fix                                                                                                     |
|---------------------------|--------------------------------------------------------------------------------------------------------|
|Scan fails / no CSV        |Check `pinefite.log` — likely a missing shared library. Ensure `LD_LIBRARY_PATH` includes `/mmc/usr/lib`|
|No networks found          |Confirm monitor interface is up: `iw dev`                                                               |
|airodump-ng missing symbols|Run `opkg install -d mmc aircrack-ng`                                                                   |
|WPS attacks fail           |Target may not have WPS enabled. Use `wash -i wlan1mon` to check                                        |

-----

## Legal

This tool is provided for **authorized security testing only**. You are responsible for ensuring you have explicit written permission before testing any network. Unauthorized access to computer networks is illegal.

-----

## Credits

Built for the Hak5 WiFi Pineapple Pager ecosystem.  
Inspired by [wifite2](https://github.com/derv82/wifite2) by derv82.
