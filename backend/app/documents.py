import os
import re
import time
import uuid

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required
from pypdf import PdfReader
from pypdf.errors import PyPdfError

from . import llm
from .metrics import (DOCUMENT_PAGES, DOCUMENTS_UPLOADED, LLM_LATENCY,
                      LLM_REQUESTS, TTS_CHUNKS_SERVED)
from .models import Document, Question, db

bp = Blueprint("documents", __name__, url_prefix="/api/documents")


def _get_doc(doc_id):
    return Document.query.filter_by(id=doc_id, user_id=int(get_jwt_identity())).first()


def _not_found():
    return jsonify(error="Document not found"), 404


def _extract(path):
    reader = PdfReader(path)
    pages = [(p.extract_text() or "") for p in reader.pages]
    text = "\n\n".join(pages)
    # Join words hyphenated across line breaks, collapse whitespace for cleaner TTS.
    text = re.sub(r"-\n(\w)", r"\1", text)
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip(), len(pages)


def split_chunks(text, start, size):
    """Yield (offset, chunk) pairs from `start`, breaking at sentence ends."""
    pos = start
    n = len(text)
    while pos < n:
        end = min(pos + size, n)
        if end < n:
            cut = max(text.rfind(". ", pos, end), text.rfind("\n", pos, end))
            if cut > pos:
                end = cut + 1
        chunk = text[pos:end].strip()
        if chunk:
            yield pos, chunk
        pos = end


@bp.post("")
@jwt_required()
def upload():
    file = request.files.get("file")
    if file is None or not file.filename:
        return jsonify(error="No file provided (field name: file)"), 400
    if not file.filename.lower().endswith(".pdf"):
        return jsonify(error="Only PDF files are supported"), 400

    upload_dir = current_app.config["UPLOAD_DIR"]
    os.makedirs(upload_dir, exist_ok=True)
    stored = os.path.join(upload_dir, f"{uuid.uuid4().hex}.pdf")
    file.save(stored)
    try:
        text, pages = _extract(stored)
    except (PyPdfError, ValueError, OSError):
        os.remove(stored)
        return jsonify(error="Could not read PDF"), 422
    if not text:
        os.remove(stored)
        return jsonify(error="No extractable text (scanned PDFs are not supported yet)"), 422

    title = request.form.get("title") or os.path.splitext(file.filename)[0]
    doc = Document(user_id=int(get_jwt_identity()), title=title[:500],
                   filename=file.filename[:500], stored_path=stored,
                   text=text, page_count=pages)
    db.session.add(doc)
    db.session.commit()
    DOCUMENTS_UPLOADED.inc()
    DOCUMENT_PAGES.observe(pages)
    return jsonify(doc.to_dict()), 201


@bp.get("")
@jwt_required()
def list_documents():
    docs = (Document.query.filter_by(user_id=int(get_jwt_identity()))
            .order_by(Document.created_at.desc()).all())
    return jsonify([d.to_dict() for d in docs])


@bp.get("/<int:doc_id>")
@jwt_required()
def get_document(doc_id):
    doc = _get_doc(doc_id)
    return jsonify(doc.to_dict(include_summary=True)) if doc else _not_found()


@bp.delete("/<int:doc_id>")
@jwt_required()
def delete_document(doc_id):
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    if os.path.exists(doc.stored_path):
        os.remove(doc.stored_path)
    db.session.delete(doc)
    db.session.commit()
    return "", 204


@bp.get("/<int:doc_id>/chunks")
@jwt_required()
def chunks(doc_id):
    """Text chunks for device TTS. `start` is a char offset; `limit` is chunk count."""
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    start = request.args.get("start", type=int, default=doc.progress_char or 0)
    limit = min(request.args.get("limit", type=int, default=10), 50)
    if start < 0:
        return jsonify(error="start must be >= 0"), 400
    size = current_app.config["TTS_CHUNK_CHARS"]
    out = []
    for offset, chunk in split_chunks(doc.text, start, size):
        out.append({"offset": offset, "text": chunk})
        if len(out) >= limit:
            break
    TTS_CHUNKS_SERVED.inc(len(out))
    return jsonify(chunks=out, text_length=len(doc.text))


@bp.put("/<int:doc_id>/progress")
@jwt_required()
def progress(doc_id):
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    value = (request.get_json(silent=True) or {}).get("progress_char")
    if not isinstance(value, int) or not 0 <= value <= len(doc.text):
        return jsonify(error="progress_char must be an integer within the text"), 400
    doc.progress_char = value
    db.session.commit()
    return jsonify(doc.to_dict())


def _call_llm(kind, fn, *args):
    start = time.perf_counter()
    try:
        result = fn(*args)
    except llm.LLMError as exc:
        LLM_REQUESTS.labels(kind, "error").inc()
        return None, (jsonify(error=str(exc)), 502)
    LLM_REQUESTS.labels(kind, "ok").inc()
    LLM_LATENCY.labels(kind).observe(time.perf_counter() - start)
    return result, None


@bp.post("/<int:doc_id>/summarize")
@jwt_required()
def summarize(doc_id):
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    if doc.summary and not request.args.get("refresh"):
        return jsonify(summary=doc.summary)
    summary, err = _call_llm("summarize", llm.summarize, doc.text)
    if err:
        return err
    doc.summary = summary
    db.session.commit()
    return jsonify(summary=summary)


@bp.post("/<int:doc_id>/ask")
@jwt_required()
def ask(doc_id):
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    question = ((request.get_json(silent=True) or {}).get("question") or "").strip()
    if not question or len(question) > 2000:
        return jsonify(error="question is required (max 2000 chars)"), 400
    answer, err = _call_llm("ask", llm.answer, doc.text, question)
    if err:
        return err
    q = Question(document_id=doc.id, question=question, answer=answer)
    db.session.add(q)
    db.session.commit()
    return jsonify(q.to_dict()), 201


@bp.get("/<int:doc_id>/history")
@jwt_required()
def history(doc_id):
    doc = _get_doc(doc_id)
    if not doc:
        return _not_found()
    qs = Question.query.filter_by(document_id=doc.id).order_by(Question.created_at).all()
    return jsonify([q.to_dict() for q in qs])
