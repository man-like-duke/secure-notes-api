from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_check():
    response = client.get("/")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_get_notes():
    response = client.get("/notes")

    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_note():
    response = client.post(
        "/notes",
        json={
            "title": "DevSecOps",
            "content": "Security gates must pass before deployment.",
        },
    )

    assert response.status_code == 200

    data = response.json()

    assert data["id"] == 1
    assert data["title"] == "DevSecOps"
    assert data["content"] == "Security gates must pass before deployment."