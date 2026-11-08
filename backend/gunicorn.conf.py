# Gunicorn settings for the container (the Dockerfile runs `gunicorn wsgi:app`,
# which reads this file). Workers are separate processes, so Prometheus metrics
# are kept in files under PROMETHEUS_MULTIPROC_DIR and added up on /metrics.
import glob
import os

bind = "0.0.0.0:8000"
workers = int(os.environ.get("GUNICORN_WORKERS", "2"))
# Long timeout: big PDFs take a while to extract on upload.
timeout = 120
accesslog = "-"
# Leave /healthz, /readyz and /metrics out of the access log (probes and
# Prometheus hit them every few seconds and would bury the real requests).
logconfig_dict = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"no_probes": {"()": "gunicorn_filters.NoProbes"}},
    "handlers": {
        "access": {
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stdout",
            "filters": ["no_probes"],
        },
        "error": {"class": "logging.StreamHandler", "stream": "ext://sys.stderr"},
    },
    "root": {"level": "WARNING", "handlers": ["error"]},
    "loggers": {
        "gunicorn.access": {"handlers": ["access"], "level": "INFO", "propagate": False},
        "gunicorn.error": {"handlers": ["error"], "level": "INFO", "propagate": False},
    },
}


def on_starting(server):
    """Start every container with empty metric files."""
    path = os.environ.get("PROMETHEUS_MULTIPROC_DIR")
    if path:
        os.makedirs(path, exist_ok=True)
        for f in glob.glob(os.path.join(path, "*.db")):
            os.remove(f)


def child_exit(server, worker):
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        from prometheus_flask_exporter.multiprocess import GunicornInternalPrometheusMetrics
        GunicornInternalPrometheusMetrics.mark_process_dead_on_child_exit(worker.pid)
