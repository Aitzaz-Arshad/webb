from datetime import datetime, timezone
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate

db = SQLAlchemy()
migrate = Migrate()

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(20), nullable=False)  # 'admin' or 'user'
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    is_active = db.Column(db.Boolean, default=True, nullable=False)

    # Relationships
    deliveries = db.relationship('Delivery', backref='sender', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'email': self.email,
            'role': self.role,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat()
        }


class Room(db.Model):
    __tablename__ = 'rooms'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    x = db.Column(db.Float, nullable=False)
    y = db.Column(db.Float, nullable=False)
    theta = db.Column(db.Float, nullable=False)
    is_robot_home = db.Column(db.Boolean, default=False, nullable=False)
    
    # 2D Floor Plan layout coordinates (stored as percentages 0.0 - 1.0)
    label_x = db.Column(db.Float, nullable=True)
    label_y = db.Column(db.Float, nullable=True)
    region_width = db.Column(db.Float, nullable=True)
    region_height = db.Column(db.Float, nullable=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'x': self.x,
            'y': self.y,
            'theta': self.theta,
            'is_robot_home': self.is_robot_home,
            'label_x': self.label_x,
            'label_y': self.label_y,
            'region_width': self.region_width,
            'region_height': self.region_height
        }


class Delivery(db.Model):
    __tablename__ = 'deliveries'

    id = db.Column(db.Integer, primary_key=True)
    sender_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    recipient_room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=False)
    pickup_room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=True)
    delivery_type = db.Column(db.String(20), nullable=False)  # 'room_to_room' or 'home_to_room'
    status = db.Column(db.String(20), default='pending', nullable=False)  # 'pending', 'picked_up', 'in_transit', 'delivered', 'failed'
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    delivered_at = db.Column(db.DateTime, nullable=True)
    recipient_name = db.Column(db.String(100), nullable=False)
    sender_name = db.Column(db.String(100), nullable=False)
    scheduled_at = db.Column(db.DateTime, nullable=True)
    is_dispatched = db.Column(db.Boolean, default=False, nullable=False)
    order_id = db.Column(db.Integer, db.ForeignKey('orders.id'), nullable=True)

    # Explicit relationships to prevent overlap on Room joins
    recipient_room = db.relationship('Room', foreign_keys=[recipient_room_id], backref='recipient_deliveries')
    pickup_room = db.relationship('Room', foreign_keys=[pickup_room_id], backref='pickup_deliveries')

    def to_dict(self):
        return {
            'id': self.id,
            'sender_id': self.sender_id,
            'sender_name': self.sender_name,
            'sender_account_name': self.sender.name if self.sender else None,
            'recipient_room_id': self.recipient_room_id,
            'recipient_room_name': self.recipient_room.name if self.recipient_room else None,
            'pickup_room_id': self.pickup_room_id,
            'pickup_room_name': self.pickup_room.name if self.pickup_room else None,
            'delivery_type': self.delivery_type,
            'recipient_name': self.recipient_name,
            'status': self.status,
            'created_at': self.created_at.isoformat(),
            'delivered_at': self.delivered_at.isoformat() if self.delivered_at else None,
            'scheduled_at': self.scheduled_at.isoformat() if self.scheduled_at else None,
            'is_dispatched': self.is_dispatched,
            'order_id': self.order_id
        }


class Order(db.Model):
    __tablename__ = 'orders'

    id = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(50), nullable=False)  # 'robo_to_room' or 'room_to_room'
    pickup_room = db.Column(db.String(100), nullable=True)  # Room name
    dropoff_room = db.Column(db.String(100), nullable=False)  # Room name
    status = db.Column(db.String(50), default='pending', nullable=False)  # 'pending', 'in_progress', 'completed'
    scheduled_time = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    completed_at = db.Column(db.DateTime, nullable=True)

    def to_dict(self):
        return {
            'id': self.id,
            'type': self.type,
            'pickup_room': self.pickup_room,
            'dropoff_room': self.dropoff_room,
            'status': self.status,
            'scheduled_time': self.scheduled_time.isoformat() if self.scheduled_time else None,
            'created_at': self.created_at.isoformat(),
            'completed_at': self.completed_at.isoformat() if self.completed_at else None
        }


class RobotState(db.Model):
    __tablename__ = 'robot_state'

    id = db.Column(db.Integer, primary_key=True)  # Singleton ID = 1
    current_status = db.Column(db.String(50), default='free', nullable=False)  # 'free', 'en_route_to_pickup', 'en_route_to_dropoff', 'returning'
    current_order_id = db.Column(db.Integer, db.ForeignKey('orders.id'), nullable=True)
    x = db.Column(db.Float, default=0.0, nullable=False)
    y = db.Column(db.Float, default=0.0, nullable=False)

    # Relationship
    current_order = db.relationship('Order', backref='robot_states', lazy=True)

    def to_dict(self):
        return {
            'current_status': self.current_status,
            'current_order_id': self.current_order_id,
            'x': self.x,
            'y': self.y
        }

class Obstacle(db.Model):
    __tablename__ = 'obstacles'

    id = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(50), default='polygon', nullable=False)
    points = db.Column(db.Text, nullable=False) # JSON-serialized coordinate points [[x1, y1], ...]

    def to_dict(self):
        import json
        return {
            'id': self.id,
            'type': self.type,
            'points': json.loads(self.points)
        }

