from flask import Blueprint, jsonify
from flask_jwt_extended import get_jwt_identity, jwt_required

from .models import Document, Question

bp = Blueprint("analytics", __name__, url_prefix="/api/analytics")


@bp.get("")
@jwt_required()
def analytics():
    """Reading stats for the logged-in user."""
    user_id = int(get_jwt_identity())
    docs = Document.query.filter_by(user_id=user_id).all()
    total_chars = sum(len(d.text or "") for d in docs)
    listened_chars = sum(d.progress_char or 0 for d in docs)
    questions = Question.query.join(Document).filter(Document.user_id == user_id).count()
    return jsonify(
        documents=len(docs),
        finished=sum(1 for d in docs if d.text and (d.progress_char or 0) >= len(d.text)),
        listened_percent=round(100 * listened_chars / total_chars) if total_chars else 0,
        questions_asked=questions,
    )
