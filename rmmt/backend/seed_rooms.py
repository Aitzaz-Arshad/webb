# seed_rooms.py
import sys
import os

# Ensure models can be imported from current directory
sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from server import app
from models import db, Room

# Define the target rooms to seed
target_rooms = [
    {
        "name": "Room 1",
        "x": -14.62,
        "y": 2.90,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.15,
        "label_y": 0.20,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Room 2",
        "x": -9.01,
        "y": 3.19,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.50,
        "label_y": 0.20,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Room 3",
        "x": -14.22,
        "y": -1.65,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.15,
        "label_y": 0.60,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Room 4",
        "x": -8.85,
        "y": -1.91,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.50,
        "label_y": 0.60,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Robot Room",
        "x": 0.0,
        "y": 0.0,
        "theta": 0.0,
        "is_robot_home": True,
        "label_x": 0.78,
        "label_y": 0.40,
        "region_width": 0.15,
        "region_height": 0.12
    }
]

def seed_rooms():
    print("Connecting to database and seeding rooms...")
    
    with app.app_context():
        inserted_count = 0
        skipped_count = 0
        
        for room_data in target_rooms:
            # Check if a room with the same name already exists
            existing_room = Room.query.filter_by(name=room_data["name"]).first()
            
            if existing_room:
                print(f"Skipping: Room with name '{room_data['name']}' already exists.")
                skipped_count += 1
            else:
                new_room = Room(
                    name=room_data["name"],
                    x=room_data["x"],
                    y=room_data["y"],
                    theta=room_data["theta"],
                    is_robot_home=room_data["is_robot_home"],
                    label_x=room_data["label_x"],
                    label_y=room_data["label_y"],
                    region_width=room_data["region_width"],
                    region_height=room_data["region_height"]
                )
                db.session.add(new_room)
                db.session.commit()
                print(f"Successfully Added: {room_data['name']} (x={room_data['x']}, y={room_data['y']}, theta={room_data['theta']}, home={room_data['is_robot_home']})")
                inserted_count += 1
                
        print("\nSeeding summary:")
        print(f"  Total rooms added: {inserted_count}")
        print(f"  Total rooms skipped (already exists): {skipped_count}")

if __name__ == '__main__':
    seed_rooms()
