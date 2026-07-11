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
                name="Robot Charging Hub (Base)",
                x=0.0,
                y=0.0,
                theta=0.0,
                is_robot_home=True
            ),
            Room(
                name="FYP Lab 101",
                x=5.2,
                y=3.5,
                theta=1.57,
                is_robot_home=False
            ),
            Room(
                name="Seminar Hall 202",
                x=12.4,
                y=-1.5,
                theta=3.14,
                is_robot_home=False
            ),
            Room(
                name="Central Library",
                x=-6.8,
                y=8.1,
                theta=-0.78,
                is_robot_home=False
            ),
            Room(
                name="Dean's Office",
                x=-2.5,
                y=-4.2,
                theta=1.57,
                is_robot_home=False
            )
        ]
        db.session.add_all(rooms)
        db.session.commit()
        
        # Save ids for reference
        home_id = rooms[0].id
        lab_id = rooms[1].id
        hall_id = rooms[2].id
        library_id = rooms[3].id
        office_id = rooms[4].id

        # 4. Seed Deliveries
        print("Creating historical and active delivery logs...")
        
        now = datetime.now(timezone.utc)
        
        deliveries = [
            Delivery(
                sender_id=student1_id,
                recipient_room_id=lab_id,
                delivery_type="home_to_room",
                status="delivered",
                created_at=now - timedelta(days=2),
                delivered_at=now - timedelta(days=2, hours=23)
            ),
            Delivery(
                sender_id=student2_id,
                pickup_room_id=library_id,
                recipient_room_id=office_id,
                delivery_type="room_to_room",
                status="delivered",
                created_at=now - timedelta(days=1),
                delivered_at=now - timedelta(days=1, hours=23, minutes=30)
            ),
            Delivery(
                sender_id=student1_id,
                recipient_room_id=hall_id,
                delivery_type="home_to_room",
                status="pending",
                created_at=now - timedelta(hours=1)
            ),
            Delivery(
                sender_id=student2_id,
                pickup_room_id=lab_id,
                recipient_room_id=library_id,
                delivery_type="room_to_room",
                status="in_transit",
                created_at=now - timedelta(minutes=15)
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
        print("\nDefault Rooms created: Charging Hub (Home), FYP Lab 101, Seminar Hall 202, Central Library, Dean's Office.")
        print(f"Default Deliveries created: 2 completed, 1 pending, 1 in transit.")

if __name__ == '__main__':
    seed_database()
