from flask import Flask, jsonify
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_migrate import Migrate
from prometheus_flask_exporter import PrometheusMetrics
from sqlalchemy import text
from werkzeug.exceptions import HTTPException

from .config import Config
from .models import db

migrate = Migrate()
jwt = JWTManager()


def create_app(config=Config):
    app = Flask(__name__)
    app.config.from_object(config)

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    CORS(app)
    PrometheusMetrics(app, group_by="url_rule", path="/metrics")

    from . import auth, documents, tts
    app.register_blueprint(auth.bp)
    app.register_blueprint(documents.bp)
    app.register_blueprint(tts.bp)

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

    @app.errorhandler(HTTPException)
    def http_error(exc):
        return jsonify(error=exc.description), exc.code

    return app
