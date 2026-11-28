from app import app

def test_health():
    resp = app.test_client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}

def test_items_not_empty():
    resp = app.test_client().get("/api/items")
    assert resp.status_code == 500
    assert len(resp.get_json()) > 0