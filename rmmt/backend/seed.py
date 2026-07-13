# seed.py
import sys
import os
from datetime import datetime, timezone, timedelta
from werkzeug.security import generate_password_hash

# Ensure models can be imported
sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from server import app
from models import db, User, Room, Delivery

def seed_database():
    print("Database seeding started...")
    
    with app.app_context():
        # 1. Clear existing database entries
        print("Clearing existing database records...")
        db.session.query(Delivery).delete()
        db.session.query(Room).delete()
        db.session.query(User).delete()
        db.session.commit()
        
        # 2. Seed Users
        print("Creating default users (hashing passwords)...")
        users = [
            User(
                name="System Administrator",
                email="admin@parcelpath.com",
                password_hash=generate_password_hash("admin123"),
                role="admin",
                is_active=True
            ),
            User(
                name="Jane Doe (Student)",
                email="student1@parcelpath.com",
                password_hash=generate_password_hash("student123"),
                role="user",
                is_active=True
            ),
            User(
                name="John Smith (Faculty)",
                email="student2@parcelpath.com",
                password_hash=generate_password_hash("student123"),
                role="user",
                is_active=True
            ),
            User(
                name="Deactivated Test Account",
                email="deactivated@parcelpath.com",
                password_hash=generate_password_hash("test1234"),
                role="user",
                is_active=False
            )
        ]
        db.session.add_all(users)
        db.session.commit()
        
        # Save ids for reference
        admin_id = users[0].id
        student1_id = users[1].id
        student2_id = users[2].id

        # 3. Seed Rooms
        print("Creating navigation room coordinates...")
        rooms = [
            Room(
                name="Room 1",
                x=-14.62,
                y=2.90,
                theta=0.0,
                is_robot_home=False,
                label_x=0.15,
                label_y=0.20,
                region_width=0.15,
                region_height=0.12
            ),
            Room(
                name="Room 2",
                x=-9.01,
                y=3.19,
                theta=0.0,
                is_robot_home=False,
                label_x=0.50,
                label_y=0.20,
                region_width=0.15,
                region_height=0.12
            ),
            Room(
                name="Room 3",
                x=-14.22,
                y=-1.65,
                theta=0.0,
                is_robot_home=False,
                label_x=0.15,
                label_y=0.60,
                region_width=0.15,
                region_height=0.12
            ),
            Room(
                name="Room 4",
                x=-8.85,
                y=-1.91,
                theta=0.0,
                is_robot_home=False,
                label_x=0.50,
                label_y=0.60,
                region_width=0.15,
                region_height=0.12
            ),
            Room(
                name="Robot Room",
                x=0.0,
                y=0.0,
                theta=0.0,
                is_robot_home=True,
                label_x=0.78,
                label_y=0.40,
                region_width=0.15,
                region_height=0.12
            )
        ]
        db.session.add_all(rooms)
        db.session.commit()
        
        # Save ids for reference
        room1_id = rooms[0].id
        room2_id = rooms[1].id
        room3_id = rooms[2].id
        room4_id = rooms[3].id
        robot_room_id = rooms[4].id

        # 4. Seed Deliveries
        print("Creating historical and active delivery logs...")
        
        now = datetime.now(timezone.utc)
        
        deliveries = [
            Delivery(
                sender_id=student1_id,
                recipient_room_id=room1_id,
                delivery_type="home_to_room",
                status="delivered",
                created_at=now - timedelta(days=2),
                delivered_at=now - timedelta(days=2, hours=23),
                recipient_name="Alice Johnson",
                sender_name="Jane Doe (Student)"
            ),
            Delivery(
                sender_id=student2_id,
                pickup_room_id=room3_id,
                recipient_room_id=room4_id,
                delivery_type="room_to_room",
                status="delivered",
                created_at=now - timedelta(days=1),
                delivered_at=now - timedelta(days=1, hours=23, minutes=30),
                recipient_name="Bob Wilson",
                sender_name="John Smith (Faculty)"
            ),
            Delivery(
                sender_id=student1_id,
                recipient_room_id=room2_id,
                delivery_type="home_to_room",
                status="pending",
                created_at=now - timedelta(hours=1),
                recipient_name="Charlie Brown",
                sender_name="Jane Doe (Student)"
            ),
            Delivery(
                sender_id=student2_id,
                pickup_room_id=room1_id,
                recipient_room_id=room3_id,
                delivery_type="room_to_room",
                status="in_transit",
                created_at=now - timedelta(minutes=15),
                recipient_name="Diana Prince",
                sender_name="John Smith (Faculty)"
            )
        ]
        db.session.add_all(deliveries)
        db.session.commit()
        
        print("\nDatabase seeded successfully!")
        print("----------------------------")
        print("Default Accounts:")
        print("  - Admin: admin@parcelpath.com  (Password: admin123)")
        print("  - User 1: student1@parcelpath.com  (Password: student123)")
        print("  - User 2: student2@parcelpath.com  (Password: student123)")
        print("  - Deactivated: deactivated@parcelpath.com (Password: test1234)")
        print("\nDefault Rooms created: Room 1, Room 2, Room 3, Room 4, Robot Room.")
        print(f"Default Deliveries created: 2 completed, 1 pending, 1 in transit.")

if __name__ == '__main__':
    seed_database()
