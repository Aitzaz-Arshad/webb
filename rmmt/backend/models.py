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
            'is_dispatched': self.is_dispatched
        }
