#!/usr/bin/env python3
"""
Push waypoints to map AND tour to DynamoDB
The tour structure is different - tour.waypoints is an array of stop data, not POI locations!
"""

import json
import requests
import time

# Your AWS API Gateway endpoint
API_ENDPOINT = "https://e536dpa128.execute-api.us-west-1.amazonaws.com/dev"

# Map ID for robotics floor
MAP_ID = "frontier_tower_floor_4"

# First, we need the waypoint LOCATIONS (these go in the map)
# These are the actual POI names that the robot knows
WAYPOINT_NAMES = [
    "start",
    "armin",
    "avatar",
    "emerson",
    "opendroids",
    "sentieverse",
    "utilitron",
    "empty_1",
    "empty_2",
    "end"
]

# The tour scripts from legacy branch
TOUR_SCRIPTS = {
    "start": "Welcome to the tour! I'll be your guide today as we explore some amazing robotics companies and innovations. Let's get started on this exciting journey.",
    "armin": "This is Armin's office, who focuses on automating laboratory workflows. His goal is to make labs faster, more efficient, and more precise through robotics. One of his current projects features a robotic arm that moves along a conveyor belt, carefully transporting samples to reduce human error and speed up everyday lab work.",
    "avatar": "Avatar Robotics supplies flexible, human-supervised industrial robot fleets for tasks like pick & place, parts handling, inspection and assembly. Their robots learn from existing employee training (no code required), scale 24/7, and adapt to changing workflows—bridging the gap where traditional automation is too rigid.",
    "emerson": "This is Emerson's office. He works on the Ultimate Fighting Bots. Ultimate Fighting Bots is the world's first robot combat league where humans pilot robots in real-time battles, live from underground arenas in San Francisco or from anywhere on the planet.",
    "opendroids": "Open Droids is a robotics startup based in the U.S. that designs, manufactures, develops, and integrates custom robotic solutions—especially mobile manipulators (robots with arms + mobility)—for industrial and transformation-use cases. They aim to reduce costs and improve efficiency for businesses by providing tailored robotic systems rather than off-the-shelf robots.",
    "sentieverse": "This office is Vivek's. He works on a product called Volu, a friendly AI alien from Sentieverse. He talks, plays, and tells stories — all screen-free. Designed for kids, Volu sparks curiosity and creativity through safe, private conversations. Every interaction is secure, and parents stay in control through the app. Volu isn't just a toy — he's a smart companion for learning and play. Scan the QR code to learn more.",
    "utilitron": "Utilitron AI & Robotics Research Laboratory is dedicated to building intelligent robots that can see, think, and act in the real world. The team's mission is to create machines with genuine perception and decision-making abilities — robots that can operate in complex environments and make people's everyday lives easier. Utilitron develops the brains behind robots — combining computer vision, language models, reinforcement learning, and emerging Vision-Language-Action (VLA) systems to create unified intelligence capable of understanding and responding to the world. Partnering with others for hardware, Utilitron aims to make its software and models robot-agnostic, enabling any platform to perceive, reason, and act intelligently across real-world tasks.",
    "empty_1": "This room is available for rent. Feel free to reach out to Katia for more information.",
    "empty_2": "This room is also available for rent. Feel free to reach out to Katia for more information.",
    "end": "Thank you for joining me on this tour! I hope you enjoyed learning about these innovative robotics companies. Have a great day!"
}

def update_map_waypoints():
    """Update the map with waypoint names"""

    print("📍 Updating map with waypoints...")

    # Get current map
    map_url = f"{API_ENDPOINT}/maps/{MAP_ID}"

    try:
        response = requests.get(map_url)
        if response.status_code == 200:
            map_data = response.json()
            print(f"   Found map: {map_data.get('name', MAP_ID)}")
        else:
            # Create map if it doesn't exist
            print("   Map not found, creating...")
            map_data = {
                "map_id": MAP_ID,
                "name": "Frontier Tower - Robotics Floor (4th)",
                "floor_id": "frontier_tower_4",
                "waypoints": []
            }
    except Exception as e:
        print(f"   Creating new map: {e}")
        map_data = {
            "map_id": MAP_ID,
            "name": "Frontier Tower - Robotics Floor (4th)",
            "floor_id": "frontier_tower_4",
            "waypoints": []
        }

    # Update waypoints list
    map_data["waypoints"] = WAYPOINT_NAMES

    # Push updated map
    headers = {"Content-Type": "application/json"}

    try:
        # Try to update
        response = requests.put(map_url, json=map_data, headers=headers)

        if response.status_code == 404:
            # Create if doesn't exist
            create_url = f"{API_ENDPOINT}/maps"
            response = requests.post(create_url, json=map_data, headers=headers)

        if response.status_code in [200, 201]:
            print(f"   ✅ Map updated with {len(WAYPOINT_NAMES)} waypoints")
            return True
        else:
            print(f"   ❌ Failed to update map: {response.status_code}")
            print(f"      {response.text}")
            return False

    except Exception as e:
        print(f"   ❌ Error updating map: {e}")
        return False

def create_tour_payload():
    """Create the tour structure with waypoint references and scripts"""

    # Build tour waypoints (these are STOPS, not POI locations)
    waypoints = []

    for waypoint_name in WAYPOINT_NAMES:
        script = TOUR_SCRIPTS.get(waypoint_name, "")

        waypoint_data = {
            "name": waypoint_name,  # This references the POI name in the map
            "speak_text": script,
            "display_url": "",  # Add URLs if you have them
            "wait_seconds": 15 if waypoint_name not in ["start", "end"] else 5
        }
        waypoints.append(waypoint_data)

    # Create the complete tour object
    tour = {
        "tour_id": "robotics_floor_tour_v1",
        "map_id": MAP_ID,
        "name": "Robotics Floor Tour",
        "description": "Guided tour of the robotics companies and labs on the 4th floor",
        "waypoints": waypoints,  # This is the tour stops with scripts
        "loop": False,
        "announce_arrival": True,
        "rest_at_end_seconds": 30,
        "intro_text": "Welcome to the Robotics Floor at Frontier Tower! I'll be your automated guide today. Please follow me as we explore these innovative companies.",
        "outro_text": "This concludes our tour of the Robotics Floor. Thank you for joining me! If you have any questions, please visit our reception.",
        "start_waypoint": "start",
        "end_waypoint": "end",
        "created_at": int(time.time() * 1000),
        "modified_at": int(time.time() * 1000)
    }

    return tour

def push_tour_to_dynamo(tour_data):
    """Push the tour to DynamoDB via API Gateway"""

    print("\n🎯 Pushing tour to DynamoDB...")

    # First, try to update existing tour
    update_url = f"{API_ENDPOINT}/tours/{tour_data['tour_id']}"

    headers = {"Content-Type": "application/json"}

    try:
        # Try PUT to update
        response = requests.put(update_url, json=tour_data, headers=headers)

        if response.status_code == 404:
            # Tour doesn't exist, create it
            print("   Creating new tour...")
            create_url = f"{API_ENDPOINT}/tours"
            response = requests.post(create_url, json=tour_data, headers=headers)
        else:
            print("   Updating existing tour...")

        if response.status_code in [200, 201]:
            print(f"   ✅ Tour pushed successfully!")
            print(f"      ID: {tour_data['tour_id']}")
            print(f"      Stops: {len(tour_data['waypoints'])}")
            return True
        else:
            print(f"   ❌ Failed to push tour: {response.status_code}")
            print(f"      {response.text}")
            return False

    except Exception as e:
        print(f"   ❌ Error pushing tour: {e}")
        return False

def main():
    print("🚀 Pushing Robotics Floor Tour to DynamoDB")
    print("=" * 50)

    # Step 1: Update map with waypoints
    map_success = update_map_waypoints()

    if not map_success:
        print("\n⚠️  Map update failed, but continuing with tour...")

    # Step 2: Create and push tour
    tour = create_tour_payload()

    print(f"\n📦 Tour prepared:")
    print(f"   Name: {tour['name']}")
    print(f"   Map: {tour['map_id']}")
    print(f"   Stops: {len(tour['waypoints'])}")

    # Show preview
    print("\n📝 Tour stops:")
    for i, wp in enumerate(tour['waypoints'], 1):
        script_preview = wp['speak_text'][:50] + "..." if len(wp['speak_text']) > 50 else wp['speak_text']
        print(f"   {i}. {wp['name']}: {script_preview}")

    # Push to DynamoDB
    tour_success = push_tour_to_dynamo(tour)

    print("\n" + "=" * 50)

    if map_success and tour_success:
        print("🎉 Complete success! Both map waypoints and tour uploaded!")
        print("\nNext steps:")
        print("1. Open Flutter app")
        print("2. Pull waypoints (to get the POI list)")
        print("3. Pull tours (to get the tour with scripts)")
        print("4. Start the tour!")
    elif tour_success:
        print("✅ Tour uploaded! You may need to manually add waypoints on the robot.")
    else:
        print("❌ Some issues occurred. Check the errors above.")

if __name__ == "__main__":
    main()