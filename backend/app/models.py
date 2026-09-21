from datetime import datetime, timezone

from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import check_password_hash, generate_password_hash

db = SQLAlchemy()


def _now():
    return datetime.now(timezone.utc)


class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_now)
    documents = db.relationship("Document", backref="owner", cascade="all, delete-orphan")

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Document(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False, index=True)
    title = db.Column(db.String(500), nullable=False)
    filename = db.Column(db.String(500), nullable=False)
    stored_path = db.Column(db.String(1000), nullable=False)
    text = db.Column(db.Text, nullable=False, default="")
    page_count = db.Column(db.Integer, default=0)
    summary = db.Column(db.Text)
    # Character offset where the user stopped listening; lets the app resume.
    progress_char = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime(timezone=True), default=_now)
    questions = db.relationship("Question", backref="document", cascade="all, delete-orphan")

    def to_dict(self, include_summary=False):
        data = {
            "id": self.id,
            "title": self.title,
            "filename": self.filename,
            "page_count": self.page_count,
            "text_length": len(self.text or ""),
            "progress_char": self.progress_char or 0,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_summary:
            data["summary"] = self.summary
        return data


class Question(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    document_id = db.Column(db.Integer, db.ForeignKey("document.id"), nullable=False, index=True)
    question = db.Column(db.Text, nullable=False)
    answer = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_now)

    def to_dict(self):
        return {
            "id": self.id,
            "question": self.question,
            "answer": self.answer,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
