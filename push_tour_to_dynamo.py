#!/usr/bin/env python3
"""
Push Robotics Floor Tour scripts directly to DynamoDB
Because copy-pasting is for chumps! 😎
"""

import json
import requests
import time
from datetime import datetime

# Your AWS API Gateway endpoint (found via my superior pattern matching skills 😏)
API_ENDPOINT = "https://e536dpa128.execute-api.us-west-1.amazonaws.com/dev"

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

def create_tour_payload():
    """Create the tour structure with all waypoints and scripts"""

    # Build waypoints list in order
    waypoints = []

    # Define the tour route order
    tour_order = [
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

    for waypoint_name in tour_order:
        script = TOUR_SCRIPTS.get(waypoint_name, "")

        waypoint = {
            "name": waypoint_name.replace("_", " ").title(),  # Pretty name
            "speak_text": script,
            "display_url": "",  # Add URLs if you have them
            "display_duration": 0,
            "wait_seconds": 15 if waypoint_name != "start" and waypoint_name != "end" else 5
        }
        waypoints.append(waypoint)

    # Create the complete tour object
    tour = {
        "tour_id": "robotics_floor_tour_v1",
        "map_id": "frontier_tower_floor_4",  # Robotics floor
        "name": "Robotics Floor Tour",
        "description": "Guided tour of the robotics companies and labs on the 4th floor",
        "waypoints": waypoints,
        "loop": False,
        "announce_arrival": True,
        "rest_at_end_seconds": 30,
        "intro_text": "Welcome to the Robotics Floor at Frontier Tower! I'll be your automated guide today. Please follow me as we explore these innovative companies.",
        "outro_text": "This concludes our tour of the Robotics Floor. Thank you for joining me! If you have any questions, please visit our reception.",
        "start_waypoint": "start",
        "end_waypoint": "end",
        "created_at": int(time.time() * 1000),
        "modified_at": int(time.time() * 1000),
        "updated_at": int(time.time() * 1000)
    }

    return tour

def push_to_dynamo(tour_data):
    """Push the tour to DynamoDB via API Gateway"""

    # First, try to update existing tour
    update_url = f"{API_ENDPOINT}/tours/{tour_data['tour_id']}"

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    try:
        # Try PUT to update
        print(f"Attempting to update tour: {tour_data['name']}...")
        response = requests.put(update_url, json=tour_data, headers=headers)

        if response.status_code == 404:
            # Tour doesn't exist, create it
            print("Tour not found, creating new...")
            create_url = f"{API_ENDPOINT}/tours"
            response = requests.post(create_url, json=tour_data, headers=headers)

        if response.status_code in [200, 201]:
            print(f"✅ Successfully pushed tour to DynamoDB!")
            print(f"   Tour ID: {tour_data['tour_id']}")
            print(f"   Waypoints: {len(tour_data['waypoints'])}")
            return True
        else:
            print(f"❌ Failed to push tour: {response.status_code}")
            print(f"   Response: {response.text}")
            return False

    except Exception as e:
        print(f"❌ Error pushing to DynamoDB: {e}")
        return False

def main():
    print("🚀 Pushing Robotics Floor Tour to DynamoDB...")
    print("=" * 50)

    # Create the tour data
    tour = create_tour_payload()

    print(f"📦 Tour prepared:")
    print(f"   Name: {tour['name']}")
    print(f"   Waypoints: {len(tour['waypoints'])}")
    print(f"   Total script words: {sum(len(w['speak_text'].split()) for w in tour['waypoints'])}")

    # Show preview
    print("\n📝 Tour stops:")
    for i, wp in enumerate(tour['waypoints'], 1):
        script_preview = wp['speak_text'][:60] + "..." if len(wp['speak_text']) > 60 else wp['speak_text']
        print(f"   {i}. {wp['name']}: {script_preview}")

    print("\n" + "=" * 50)

    # Push to DynamoDB
    if API_ENDPOINT.startswith("https://YOUR_API_ID"):
        print("⚠️  Please update API_ENDPOINT in this script with your actual endpoint!")
        print("   You can get it from: aws cloudformation describe-stacks --stack-name frontiertower-stack")
        print("\n📋 Here's the tour data as JSON (copy/paste to API):\n")
        print(json.dumps(tour, indent=2))
    else:
        success = push_to_dynamo(tour)
        if success:
            print("\n🎉 Tour successfully uploaded to cloud!")
            print("   Open your Flutter app and pull tours to see it!")

if __name__ == "__main__":
    main()