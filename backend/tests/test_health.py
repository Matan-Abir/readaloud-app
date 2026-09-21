def test_health_and_ready(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_metrics_exposed(client):
    client.get("/healthz")
    body = client.get("/metrics").get_data(as_text=True)
    assert "flask_http_request_total" in body
