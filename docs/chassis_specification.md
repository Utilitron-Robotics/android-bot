# Mobile Robot Chassis Specification
## Intelligent Mobile Robot Platform

> **Related Documentation:**
> - [`chassis_protocol.md`](chassis_protocol.md) - WebSocket API protocol specification
> - [`../ROBOT_PROTOCOL.md`](../ROBOT_PROTOCOL.md) - Field-tested implementation notes
> - [`../NETWORKING.md`](../NETWORKING.md) - Network topology and connection types

## 1. Product Overview
This intelligent mobile robot platform serves as the core structure for robotic solutions. Designed for durability, adaptability, and precision, this chassis features advanced mobility systems, modular compatibility, and robust materials. It seamlessly integrates multi-sensor fusion, SLAM-based positioning and mapping, multiple operational modes, and coordinated multi-robot operation. Enhanced by cloud-based management, IoT control systems, automated charging, and flexible motion control.

## 2. Product Specifications

### 2.1 Basic Information
| Parameter | Specs |
|-----------|-------|
| Dimensions | 500mmL * 500mmW * 310mmH |
| Weight | 35kg |
| Max Load | 59kg |
| No-load Battery Life | 12h |
| Charging Time | 4h |
| Maximum Load Capacity | 50kg |
| Battery Capacity | 24V/20AH = 480Wh |
| Chassis Form | 2x Drive Wheels + 4x Omni-directional + 1x Fixed Wheel |
| Maximum Navigation Speed | 0.8m/s (Adjustable Speed) |
| Obstacle Avoidance Distance | 80cm |
| Chassis Inclination | 5° |
| Obstacle Clearance Height | 10mm |
| Minimum Obstacle Clearance | 40mm |
| Turning Radius | 0mm |
| Maximum Rotation Speed | 60°/s |
| Positioning Accuracy | ±5cm |
| Mapping Area | 10000m² (Up to 30000m²) |
| Repeat Positioning Accuracy | ±5cm |

### 2.2 Expansion Interface
| Parameter | Specs |
|-----------|-------|
| Power Input Interface | 24V (200W Power) |
| USB Ports | 2 Ports, Expandable |
| Network Interface | RJ45, Optional Wireless Network |
| Physical Expansion Interface | Structural Accessories |
| Other Interfaces | System Switch, Thermal Switch |

### 2.3 Charging Parameters
| Parameter | Specs |
|-----------|-------|
| Input Voltage | AC 110-240V |
| Output Voltage | 29.4V |
| Maximum Charging Current | 7A |
| Protection Mechanism | Short Circuit, Overcurrent, etc. |

### 2.4 Environmental Requirements
| Parameter | Specs |
|-----------|-------|
| Storage Temperature | -10°C~60°C |
| Operating Temperature | 5°C~40°C |

## 3. API Port Interface
| No. | Function | Description |
|-----|----------|-------------|
| 1 | Network Connection | WebSocket server connection/disconnection |
| 2 | Robot Position | Coordinates of the robot on the map |
| 3 | Full Status Information | Battery level, navigation status, emergency stop, floor name |
| 4 | Complete Map Data | Display map |
| 5 | Radar Data | Display radar data |
| 6 | Navigation Path Planning | Display the planned navigation path |
| 7 | Navigation Status | Current navigation status |
| 8 | Detailed Recharge Status | Recharging status information |
| 9 | Speed Control | Manual remote control of the robot |
| 10 | Publish Target Point | Select a point on the map for navigation |
| 11 | Cancel Navigation | Cancel current navigation |
| 12 | Set Initial Position | Set initial position on map |
| 13 | Set Recharge Dock Position | Set recharge dock position |
| 14 | Soft Emergency Stop | Enable/disable soft emergency stop |
| 15-16 | Virtual Wall Setting | Set/append virtual wall information |
| 17-19 | Mark Point Management | Set/append/insert mark points |
| 20 | Map Editing | Interface for map editing |
| 21 | Recharge Dock Alignment | Start infrared alignment |
| 22 | Program Control | Switch between mapping/navigation modes |
| 23-24 | Map Management | List/delete maps |
| 25-27 | Mark Point Operations | Get/delete mark points |
| 28-30 | Virtual Wall Operations | Get/delete virtual walls |
| 31 | Navigate by Name | Navigate to specific point |
| 32 | Set Position by Name | Set initial position by name |
| 33 | Multi-Point Navigation | Start/stop multi-point navigation |
| 34 | Recharge Control | Start/stop recharging |
| 35 | Get Map Metadata | Retrieve coordinate origin and dimensions |
| 36 | Modify Navigation Speed | Adjust movement speed |
| 37 | Version Update | Update code via USB or network |

## 4. Product Functions
| No. | Function | Description |
|-----|----------|-------------|
| 1 | Mapping | SLAM algorithm for incremental mapping with loop closure |
| 2 | High-Precision Localization | Sensor-based localization in known maps |
| 3 | Path Planning | Efficient path planning to target points |
| 4 | Autonomous Obstacle Avoidance | Avoid obstacles during navigation |
| 5 | Autonomous Charging | Return to charging dock when battery low |
| 6 | Multi-Point Navigation | Execute multi-point navigation programs |
| 7 | Ultrasonic Obstacle Avoidance | Detect glass and special obstacles |
| 8 | Floor Map Management | Save/load maps by building and floor |
| 9 | Map Management | Save/load mapping information |
| 10 | Map Editing | Edit maps to optimize display |
| 11 | Wireless Remote Control | Control via mobile app |
| 12 | Virtual Wall | Restrict robot from specific areas |
| 13 | Upper-Level Communication | Network communication interface |
| 14 | Depth Camera Obstacle Avoidance | 3D obstacle detection |
| 15 | Emergency Stop | Software and hardware emergency stop |
| 16 | Manual Relocation | Manual position setting on map |
| 17 | Code Updates | Network or USB updates |
| 18 | Dynamic Speed Adjustment | Different speed modes |
| 19 | Mark Point Management | Set attributes for marked points |
| 20 | Global Self-Localization | Auto-calibrate position on map |

## 5. External Connection Interface
1. **Power Port**: 24V/10A with overcurrent and short circuit protection
   - Pin 1.1: Positive
   - Pin 1.3: Negative

2. **USB Expansion**: USB 2.0 ports x2

3. **Network Port**: TCP/IP protocol for chassis communication
   - Upper Port: Camera
   - Lower Port: External USB

4. **Switch Interface**: Emergency stop connection
   - Pins 4.2, 4.3: Emergency stop
   - Pins 4.5, 4.6: System startup

PIN Pitch Connector: 5.08mm and 3.81mm
