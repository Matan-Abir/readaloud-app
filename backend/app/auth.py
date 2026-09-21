from flask import Blueprint, jsonify, request
from flask_jwt_extended import create_access_token
from sqlalchemy.exc import IntegrityError

from .metrics import USERS_REGISTERED
from .models import User, db

bp = Blueprint("auth", __name__, url_prefix="/api/auth")


def _credentials():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    return email, password


@bp.post("/register")
def register():
    email, password = _credentials()
    if "@" not in email or len(email) > 255:
        return jsonify(error="A valid email is required"), 400
    if len(password) < 8:
        return jsonify(error="Password must be at least 8 characters"), 400
    user = User(email=email)
    user.set_password(password)
    db.session.add(user)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify(error="Email already registered"), 409
    USERS_REGISTERED.inc()
    return jsonify(id=user.id, email=user.email), 201


@bp.post("/login")
def login():
    email, password = _credentials()
    user = User.query.filter_by(email=email).first()
    if user is None or not user.check_password(password):
        return jsonify(error="Invalid credentials"), 401
    token = create_access_token(identity=str(user.id))
    return jsonify(access_token=token)
