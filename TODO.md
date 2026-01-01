# TODO

## Security (PRIORITY)
- [ ] Change robot WiFi hotspot passwords (currently `123456789` - cracked in 1 day)
  - SSH into robot base at `10.42.0.1`
  - Find hostapd config: `find /etc -name "*hostapd*"`
  - Update `wpa_passphrase` to strong password
  - Restart WiFi service
  - Update CLAUDE.md with new credentials

## In Progress
- [ ] Fix Flutter ↔ Relay WebSocket connection bouncing
  - Added 60s socket timeout
  - Added server-side ping every 10s
  - Added ping/pong message handling
  - Testing...

## Completed
- [x] AWS Fleet Config backend deployed
- [x] Fleet API client in relay app
- [x] Fleet API client in Flutter app
- [x] Google Cloud TTS integration with caching
- [x] Tour Mode implementation
  - TourMode data model (tour_mode.dart) with Tour and TourStop classes
  - TourManager for saving/loading/executing tours
  - TourEditor UI widget for creating and editing tours
  - TourExecutor service connecting tours to robot navigation
  - Supports: speak text, display URL/image at each stop
  - Reorderable stops with drag-and-drop
