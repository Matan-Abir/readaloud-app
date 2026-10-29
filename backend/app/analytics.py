from flask import Blueprint, jsonify
from flask_jwt_extended import get_jwt_identity, jwt_required

from sqlalchemy import func

from .models import Document, Question, db

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
    # The two figures the course catalog asks for: most queried documents and
    # average summary length.
    counts = dict(db.session.query(Question.document_id, func.count(Question.id))
                  .filter(Question.document_id.in_([d.id for d in docs]))
                  .group_by(Question.document_id).all()) if docs else {}
    most_asked = sorted((d for d in docs if counts.get(d.id)),
                        key=lambda d: (-counts[d.id], d.id))[:5]
    summaries = [len(d.summary) for d in docs if d.summary]
    return jsonify(
        documents=len(docs),
        finished=sum(1 for d in docs if d.text and (d.progress_char or 0) >= len(d.text)),
        listened_percent=round(100 * listened_chars / total_chars) if total_chars else 0,
        questions_asked=questions,
        most_asked=[{"id": d.id, "title": d.title, "questions": counts[d.id]} for d in most_asked],
        avg_summary_chars=round(sum(summaries) / len(summaries)) if summaries else 0,
    )
