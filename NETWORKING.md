# Robot Networking Architecture

## Physical Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                         HOUSE WIFI NETWORK                          │
│                                                                     │
│   ┌─────────────┐                      ┌──────────────────────┐    │
│   │ Flutter App │◄────── WS :8766 ────►│                      │    │
│   │  (Phone/PC) │                      │   ANDROID TABLET     │    │
│   └─────────────┘                      │   (Relay Server)     │    │
│                                        │                      │    │
│   ┌─────────────┐                      │   HTTP :8765 (WAN)   │    │
│   │ Cloud/WAN   │◄────── HTTP ────────►│   WS :8766 (LAN)     │    │
│   └─────────────┘                      │                      │    │
│                                        └──────────┬───────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                                    │
                                              WIRED / USB
                                            192.168.20.22:9090
                                                    │
                                         ┌──────────┴──────────┐
                                         │    ROBOT BASE       │
                                         │  (Robot/chassis)       │
                                         │                     │
                                         │  Also broadcasts:   │
                                         │  WiFi Hotspot       │
                                         │  MobileBase003F0-XXXXX │
                                         │  → 10.42.0.1:9090   │
                                         └─────────────────────┘
```

## Connection Types

### 1. WS Relay (Port 8766) - PRIMARY for LAN
- **Use case**: Flutter apps on house WiFi controlling robot
- **Path**: Flutter → Tablet WS :8766 → Wired → Robot Base
- **Protocol**: WebSocket (bidirectional, real-time)
- **When**: Normal operation

### 2. HTTP Relay (Port 8765) - For WAN Access
- **Use case**: Cloud/remote control, REST API calls
- **Path**: Cloud/WAN → Tablet HTTP :8765 → Wired → Robot Base
- **Protocol**: HTTP REST
- **When**: Remote monitoring, cloud integration

### 3. Direct WiFi (10.42.0.1) - DIAGNOSTICS ONLY
- **Use case**: Maintenance, firmware updates, diagnostics
- **Path**: Tech device → Robot WiFi hotspot → Robot Base
- **Protocol**: WebSocket direct to rosbridge
- **When**: Tablet/relay unavailable, tech maintenance
- **Robot WiFi SSIDs**: MobileBase003F0-005878, MobileBase003F0-005993
- **Password**: 123456789

## IP Addresses

| Connection | IP Address | Port | Purpose |
|------------|------------|------|---------|
| Tablet → Robot (WIRED) | 192.168.20.22 | 9090 | Relay's connection to robot |
| Direct WiFi Hotspot | 10.42.0.1 | 9090 | Tech/diagnostics only |
| Flutter → Tablet WS | tablet-ip | 8766 | LAN control |
| Cloud → Tablet HTTP | tablet-ip | 8765 | WAN/REST access |

## Key Points

1. **The tablet is WIRED to the robot base** - Uses 192.168.20.22
2. **The relay app connects to 192.168.20.22** - NOT the WiFi hotspot
3. **10.42.0.1 is for direct diagnostics** - Only when relay is unavailable
4. **Flutter apps NEVER connect directly to robot** - Always through relay
5. **Tablet does NOT connect to robot's WiFi** - Already wired, no need to multi-home

## Why Use a Relay?

1. **Controlled access** - Single point of communication to robot
2. **House WiFi coverage** - Reliable throughout the building
3. **Wired = reliable** - USB connection to robot never drops
4. **Security** - Robot's weak WiFi is intentional; direct access requires close proximity

## Why Tablet Doesn't Use Robot's WiFi

The tablet COULD connect its WiFi to the robot's hotspot (10.42.0.1), but there's no purpose:
- It's already wired on the 192.168.20.22 subnet
- Android won't multi-home to use both networks simultaneously
- The wired connection is faster and more reliable
- The robot's WiFi hotspot is only useful for OTHER devices (phones, laptops) doing close-range diagnostics

## Relay App Configuration

The relay app (Android tablet) should ALWAYS use:
```
ROBOT_IP = "192.168.20.22"  // Wired connection
ROBOT_PORT = 9090
```

The 10.42.0.1 address is ONLY used by Flutter/diagnostic tools when connecting directly to the robot's WiFi hotspot for maintenance.
