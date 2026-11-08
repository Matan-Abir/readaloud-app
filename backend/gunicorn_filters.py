import logging

QUIET_PATHS = ("/healthz", "/readyz", "/metrics")


class NoProbes(logging.Filter):
    """Drops access-log lines for health checks and Prometheus scrapes."""

    def filter(self, record):
        args = record.args if isinstance(record.args, dict) else {}
        path = args.get("U", "")
        return path not in QUIET_PATHS
