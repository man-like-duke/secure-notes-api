from fastapi import FastAPI
from pydantic import BaseModel


app = FastAPI(
    title="Secure Notes API",
    version="0.1.0",
)


class Note(BaseModel):
    title: str
    content: str


notes: list[dict] = []


@app.get("/")
def health_check():
    return {
        "status": "healthy",
        "service": "secure-notes-api",
        "version": "0.1.0",
    }


@app.get("/notes")
def get_notes():
    return notes


@app.post("/notes")
def create_note(note: Note):
    new_note = {
        "id": len(notes) + 1,
        "title": note.title,
        "content": note.content,
    }

    notes.append(new_note)

    return new_note

def unsafe_example(user_input):
    return eval(user_input)