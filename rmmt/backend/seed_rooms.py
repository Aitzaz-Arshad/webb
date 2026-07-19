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
        "x": -14.861900,
        "y": 2.165460,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.15,
        "label_y": 0.20,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Room 2",
        "x": -8.937850,
        "y": 3.330800,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.50,
        "label_y": 0.20,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Room 3",
        "x": -14.934200,
        "y": -1.483210,
        "theta": 0.0,
        "is_robot_home": False,
        "label_x": 0.15,
        "label_y": 0.60,
        "region_width": 0.15,
        "region_height": 0.12
    },
    {
        "name": "Robot Room",
        "x": -0.033712,
        "y": 0.018029,
        "theta": 0.0,
        "is_robot_home": True,
        "label_x": 0.78,
        "label_y": 0.40,
        "region_width": 0.15,
        "region_height": 0.12
    }
]

def seed_rooms():
    print("Connecting to database and seeding/updating rooms...")
    
    with app.app_context():
        inserted_count = 0
        updated_count = 0
        
        for room_data in target_rooms:
            # Check if a room with the same name already exists
            existing_room = Room.query.filter_by(name=room_data["name"]).first()
            
            if existing_room:
                print(f"Updating existing room: '{room_data['name']}' (x={room_data['x']}, y={room_data['y']})")
                existing_room.x = room_data["x"]
                existing_room.y = room_data["y"]
                existing_room.theta = room_data["theta"]
                existing_room.is_robot_home = room_data["is_robot_home"]
                existing_room.label_x = room_data["label_x"]
                existing_room.label_y = room_data["label_y"]
                existing_room.region_width = room_data["region_width"]
                existing_room.region_height = room_data["region_height"]
                db.session.commit()
                updated_count += 1
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
                
        print("\nSeeding/updating summary:")
        print(f"  Total rooms added: {inserted_count}")
        print(f"  Total rooms updated: {updated_count}")

if __name__ == '__main__':
    seed_rooms()
