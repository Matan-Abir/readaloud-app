from flask import Flask, jsonify
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_migrate import Migrate
from prometheus_flask_exporter import PrometheusMetrics
from sqlalchemy import text
from werkzeug.exceptions import HTTPException, RequestEntityTooLarge

from .config import Config
from .models import db

migrate = Migrate()
jwt = JWTManager()


# Token problems answer like every other error: 401 with {"error": ...}.
@jwt.unauthorized_loader
def _missing_token(reason):
    return jsonify(error="Missing or malformed Authorization header"), 401


@jwt.invalid_token_loader
def _invalid_token(reason):
    return jsonify(error="Invalid token"), 401


@jwt.expired_token_loader
def _expired_token(header, payload):
    return jsonify(error="Token has expired, please log in again"), 401


def create_app(config=Config):
    app = Flask(__name__)
    app.config.from_object(config)

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    CORS(app)
    PrometheusMetrics(app, group_by="url_rule", path="/metrics")

    from . import analytics, auth, documents, tts
    app.register_blueprint(auth.bp)
    app.register_blueprint(documents.bp)
    app.register_blueprint(tts.bp)
    app.register_blueprint(analytics.bp)

    @app.get("/healthz")
    def healthz():
        """Liveness: the process is up and serving."""
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        """Readiness: the database is reachable."""
        try:
            db.session.execute(text("SELECT 1"))
        except Exception:
            return jsonify(status="db unavailable"), 503
        return jsonify(status="ready")

    @app.errorhandler(RequestEntityTooLarge)
    def too_large(exc):
        limit_mb = app.config["MAX_CONTENT_LENGTH"] // (1024 * 1024)
        return jsonify(error=f"File is too large (max {limit_mb} MB)"), 413

    @app.errorhandler(HTTPException)
    def http_error(exc):
        return jsonify(error=exc.description), exc.code

    @app.errorhandler(Exception)
    def unexpected_error(exc):
        app.logger.exception("Unhandled error")
        return jsonify(error="Internal server error"), 500

    return app
